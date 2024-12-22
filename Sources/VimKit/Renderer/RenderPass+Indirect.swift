//
//  RenderPass+Indirect.swift
//  VimKit
//
//  Created by Kevin McKee
//
import Combine
import MetalKit
import VimKitShaders

private let functionNameVertex = "vertexMain"
private let functionNameVertexDepthOnly = "vertexDepthOnly"
private let functionNameFragment = "fragmentMain"
private let functionNameEncodeIndirectRenderCommands = "encodeIndirectRenderCommands"
private let functionNameDepthPyramid = "depthPyramid"
private let labelICB = "IndirectCommandBuffer"
private let labelICBAlphaMask = "IndirectCommandBufferAlphaMask"
private let labelICBTransparent = "IndirectCommandBufferTransparent"
private let labelICBDepthOnly = "IndirectCommandBufferDepthOnly"
private let labelICBDepthOnlyAlphaMask = "IndirectCommandBufferDepthOnlyAlphaMask"
private let labelPipeline = "IndirectRendererPipeline"
private let labelPipelineNoDepth = "IndirectRendererPipelineNoDepth"
private let labelRenderEncoder = "RenderEncoderIndirect"
private let labelDepthPyramidGeneration = "DepthPyramidGeneration"
private let labelTextureDepth = "DepthTexture"
private let labelTextureDepthPyramid = "DepthPyramidTexture"
private let maxBufferBindCount = 24
private let maxCommandCount = 1024 * 64
private let maxExecutionRange = 1024 * 16

/// Provides an indirect render pass using indirect command buffers.
class RenderPassIndirect: RenderPass {

    /// A container that holds all of the icb data.
    struct ICB {
        /// The default indirect command buffers
        var commandBuffer: MTLIndirectCommandBuffer
        var commandBufferAlphaMask: MTLIndirectCommandBuffer
        var commandBufferTransparent: MTLIndirectCommandBuffer
        /// The indirect command buffers used for depth only
        var commandBufferDepthOnly: MTLIndirectCommandBuffer
        var commandBufferDepthOnlyAlphaMask: MTLIndirectCommandBuffer
        /// A metal buffer storing the icb execution range
        var indirectRangeBuffer: MTLBuffer
        /// The number of execution ranges.
        var indirectRangeCount: Int
        /// The icb encodeer arguments buffers consisting of MTLArgumentEncoders
        var argumentEncoder: MTLBuffer
        var argumentEncoderAlphaMask: MTLBuffer
        var argumentEncoderTransparent: MTLBuffer
        /// A metal buffer for keep track of executed commands storing a single byte per command.
        var executedCommandsBuffer: MTLBuffer?
    }

    /// The context that provides all of the data we need
    let context: RendererContext

    /// Boolean flag indicating if indirect command buffers should perform depth occlusion testing or not.
    /// Frustum testing will always happen
    open var enableDepthTesting: Bool {
        context.vim.options.enableDepthTesting
    }

    /// The icb container.
    var icb: ICB?

    /// The compute pipeline state.
    private var computeFunction: MTLFunction?
    private var computePipelineState: MTLComputePipelineState?
    /// The render pipeline stae.
    private var pipelineState: MTLRenderPipelineState?
    private var pipelineStateDepthOnly: MTLRenderPipelineState?
    private var depthStencilState: MTLDepthStencilState?
    private var samplerState: MTLSamplerState?

    /// Combine subscribers.
    var subscribers = Set<AnyCancellable>()

    /// Initializes the render pass with the provided rendering context.
    /// - Parameter context: the rendering context.
    init?(_ context: RendererContext) {
        self.context = context
        guard let library = makeLibrary() else { return nil }

        let vertexDescriptor = makeVertexDescriptor()
        self.pipelineState = makeRenderPipelineState(context, vertexDescriptor, labelPipeline, functionNameVertex, functionNameFragment)
        self.pipelineStateDepthOnly = makeDepthOnlyPipelineState(library)
        self.depthStencilState = makeDepthStencilState()
        self.samplerState = makeSamplerState()
        makeComputePipelineState(library)

        context.vim.geometry?.$state.sink { [weak self] state in
            guard let self, let geometry else { return }
            switch state {
            case .ready:

                let gridSize = geometry.gridSize

                // Update the stats
                context.vim.stats.instanceCount = geometry.instances.count
                context.vim.stats.meshCount = geometry.meshes.count
                context.vim.stats.submeshCount = geometry.submeshes.count
                context.vim.stats.gridSize = gridSize

                let totalCommands = gridSize.width * gridSize.height
                debugPrint("􀬨 Building indirect command buffers [\(totalCommands)]")
                makeIndirectCommandBuffers(totalCommands)
            case .indexing, .loading, .unknown, .error:
                break
            }
        }.store(in: &subscribers)
    }

    /// Performs all encoding and setup options before drawing.
    /// - Parameters:
    ///   - descriptor: the draw descriptor
    func willDraw(descriptor: DrawDescriptor) {

        // 1) Reset the commands in the icb
        reset(descriptor: descriptor);

        guard let computeEncoder = descriptor.commandBuffer.makeComputeCommandEncoder() else { return }

        // 2) Encode the buffers onto the comute encoder
        encode(descriptor: descriptor, computeEncoder: computeEncoder)

        // 3) End the compute encoding
        computeEncoder.endEncoding()

        // 4) Optimize the icb commands (optional but let's do it anyway)
        optimize(descriptor: descriptor)
    }

    /// Performs a draw call with the specified command buffer and render pass descriptor.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    func draw(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {

        // Encode the buffers
        encode(descriptor: descriptor, renderEncoder: renderEncoder)

        // Make the draw calls
        drawIndirect(descriptor: descriptor, renderEncoder: renderEncoder)

        // Consume the culling results and publish stats
        collect()
    }

    /// Encodes the buffer data into the compute encoder.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the compute encoder to use
    private func encode(descriptor: DrawDescriptor, computeEncoder: MTLComputeCommandEncoder) {
        guard let geometry,
              let computePipelineState,
              let icb,
              let framesBuffer = descriptor.framesBuffer,
              let lightsBuffer = descriptor.lightsBuffer,
              let depthTexture = descriptor.depthTexture,
              let executedCommandsBuffer = icb.executedCommandsBuffer,
              let positionsBuffer = geometry.positionsBuffer,
              let normalsBuffer = geometry.normalsBuffer,
              let indexBuffer = geometry.indexBuffer,
              let instancesBuffer = geometry.instancesBuffer,
              let instancedMeshesBuffer = geometry.instancedMeshesBuffer,
              let meshesBuffer = geometry.meshesBuffer,
              let submeshesBuffer = geometry.submeshesBuffer,
              let materialsBuffer = geometry.materialsBuffer,
              let colorsBuffer = geometry.colorsBuffer else { return }

        // 1) Encode
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setBuffer(framesBuffer, offset: descriptor.framesBufferOffset, index: .frames)
        computeEncoder.setBuffer(lightsBuffer, offset: 0, index: .lights)
        computeEncoder.setBuffer(positionsBuffer, offset: 0, index: .positions)
        computeEncoder.setBuffer(normalsBuffer, offset: 0, index: .normals)
        computeEncoder.setBuffer(indexBuffer, offset: 0, index: .indexBuffer)
        computeEncoder.setBuffer(instancesBuffer, offset: 0, index: .instances)
        computeEncoder.setBuffer(instancedMeshesBuffer, offset: 0, index: .instancedMeshes)
        computeEncoder.setBuffer(meshesBuffer, offset: 0, index: .meshes)
        computeEncoder.setBuffer(submeshesBuffer, offset: 0, index: .submeshes)
        computeEncoder.setBuffer(materialsBuffer, offset: 0, index: .materials)
        computeEncoder.setBuffer(colorsBuffer, offset: 0, index: .colors)
        computeEncoder.setBuffer(icb.argumentEncoder, offset: 0, index: .commandBufferContainer)
        computeEncoder.setBuffer(executedCommandsBuffer, offset: 0, index: .executedCommands)
        computeEncoder.setTexture(depthTexture, index: 0)

        // 2) Use Resources
        computeEncoder.useResource(icb.commandBuffer, usage: .read)
        computeEncoder.useResource(executedCommandsBuffer, usage: .write)
        computeEncoder.useResource(framesBuffer, usage: .read)
        computeEncoder.useResource(materialsBuffer, usage: .read)
        computeEncoder.useResource(instancesBuffer, usage: .read)
        computeEncoder.useResource(instancedMeshesBuffer, usage: .read)
        computeEncoder.useResource(meshesBuffer, usage: .read)
        computeEncoder.useResource(submeshesBuffer, usage: .read)
        computeEncoder.useResource(meshesBuffer, usage: .read)
        computeEncoder.useResource(indexBuffer, usage: .read)
        computeEncoder.useResource(depthTexture, usage: .read)

        // 3) Dispatch the threads
        let gridSize = geometry.gridSize
        let w = computePipelineState.threadExecutionWidth
        let h = computePipelineState.maxTotalThreadsPerThreadgroup / w
        let threadgroupSize: MTLSize = .init(width: w, height: h, depth: 1)
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
    }

    /// Encodes the buffer data into the render encoder.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func encode(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {
        guard let pipelineState else { return }
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(options.cullMode)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setTriangleFillMode(fillMode)
    }

    /// Execute the commands in the indirect command buffer.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func drawIndirect(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {
        guard let icb else { return }
        for i in 0..<icb.indirectRangeCount {
            let offset = MemoryLayout<MTLIndirectCommandBufferExecutionRange>.size * i
            renderEncoder.executeCommandsInBuffer(icb.commandBuffer, indirectBuffer: icb.indirectRangeBuffer, offset: offset)
        }
    }

    /// Resets the commands in the indirect command buffer.
    /// - Parameters:
    ///   - descriptor: the draw descriptor
    ///   - renderEncoder: the render encoder
    private func reset(descriptor: DrawDescriptor) {
        guard let icb, let blitEncoder = descriptor.commandBuffer.makeBlitCommandEncoder() else { return }
        let range = 0..<icb.commandBuffer.size
        blitEncoder.resetCommandsInBuffer(icb.commandBuffer, range: range)
        blitEncoder.endEncoding()
    }

    /// Encodes a command that can improve the performance of a range of commands within an indirect command buffer.
    /// - Parameters:
    ///   - descriptor: the draw descriptor
    private func optimize(descriptor: DrawDescriptor) {
        guard let icb, let blitEncoder = descriptor.commandBuffer.makeBlitCommandEncoder() else { return }
        let range = 0..<icb.commandBuffer.size
        blitEncoder.optimizeIndirectCommandBuffer(icb.commandBuffer, range: range)
        blitEncoder.endEncoding()
    }

    /// Consumes the culling results from the icb and publishes the stats.
    private func collect() {
        guard let icb else { return }
        if let executedCommandsBuffer = icb.executedCommandsBuffer {
            Task {
                let range: UnsafeMutableBufferPointer<UInt8> = executedCommandsBuffer.toUnsafeMutableBufferPointer()
                let count = range.filter{ $0 == 1 }.count
                context.vim.stats.executedCommands = count
            }
        }
    }

    /// Draws the depth pyramid offscreen.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func drawDepthOffscreen(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {

        guard let geometry,
              let pipelineStateDepthOnly,
              let positionsBuffer = geometry.positionsBuffer,
              let indexBuffer = geometry.indexBuffer else { return }

        renderEncoder.setRenderPipelineState(pipelineStateDepthOnly)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setCullMode(.back)
        renderEncoder.setTriangleFillMode(fillMode)

        // Setup the per frame buffers to pass to the GPU
        renderEncoder.setVertexBuffer(descriptor.framesBuffer, offset: descriptor.framesBufferOffset, index: .frames)
        renderEncoder.setVertexBuffer(positionsBuffer, offset: 0, index: .positions)

        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: geometry.indices.count,
            indexType: .uint32,
            indexBuffer: indexBuffer, indexBufferOffset: 0
        )
    }

    /// Makes a depth only pipeline state
    /// - Parameter library: the library to use
    /// - Returns: the depth only pipeline state
    private func makeDepthOnlyPipelineState(_ library: MTLLibrary) -> MTLRenderPipelineState? {

        let vertexFunction = makeFunction(library, functionNameVertexDepthOnly)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .invalid
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineDescriptor.label = labelPipelineNoDepth

        return try? device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    /// Makes the compute pipeline state.
    /// - Parameter library: the metal library
    private func makeComputePipelineState(_ library: MTLLibrary) {

        guard supportsIndirectCommandBuffers else {
            debugPrint("💩 Indirect command buffers are not supported on this device.")
            return
        }

        // Make the compute pipeline state
        guard let computeFunction = library.makeFunction(name: functionNameEncodeIndirectRenderCommands),
              let computePipelineState = try? device.makeComputePipelineState(function: computeFunction) else { return }
        self.computePipelineState = computePipelineState
        self.computeFunction = computeFunction
    }

    /// Makes the indirect command buffer struct.
    /// - Parameter totalCommands: the total amount of commands the indirect command buffer supports.
    private func makeIndirectCommandBuffers(_ totalCommands: Int = maxCommandCount) {

        guard let computeFunction else { return }

        // Make the indirect command buffer descriptor
        let descriptor = MTLIndirectCommandBufferDescriptor()
        descriptor.commandTypes = [.drawIndexed]
        descriptor.inheritBuffers = false
        descriptor.inheritPipelineState = true
        descriptor.maxVertexBufferBindCount = maxBufferBindCount
        descriptor.maxFragmentBufferBindCount = maxBufferBindCount

        // Make the indirect command buffers and label them
        guard let commandBuffer = device.makeIndirectCommandBuffer(descriptor: descriptor, maxCommandCount: totalCommands),
              let commandBufferAlphaMask = device.makeIndirectCommandBuffer(descriptor: descriptor, maxCommandCount: totalCommands),
              let commandBufferTransparent = device.makeIndirectCommandBuffer(descriptor: descriptor, maxCommandCount: totalCommands),
              let commandBufferDepthOnly = device.makeIndirectCommandBuffer(descriptor: descriptor, maxCommandCount: totalCommands),
              let commandBufferDepthOnlyAlphaMask = device.makeIndirectCommandBuffer(descriptor: descriptor, maxCommandCount: totalCommands) else { return }

        commandBuffer.label = labelICB
        commandBufferAlphaMask.label = labelICBAlphaMask
        commandBufferTransparent.label = labelICBTransparent
        commandBufferDepthOnly.label = labelICBDepthOnly
        commandBufferDepthOnlyAlphaMask.label = labelICBDepthOnlyAlphaMask

        // Make the execution range buffer
        let indirectRangeResult = makeIndirectRange(totalCommands)
        guard let indirectRangeBuffer = indirectRangeResult.buffer else { return }
        let indirectRangeCount = indirectRangeResult.count

        // Make the argument encoders
        let icbArgumentEncoder = computeFunction.makeArgumentEncoder(.commandBufferContainer)
        guard let argumentEncoder = device.makeBuffer(length: icbArgumentEncoder.encodedLength),
              let argumentEncoderAlphaMask = device.makeBuffer(length: icbArgumentEncoder.encodedLength),
              let argumentEncoderTransparent = device.makeBuffer(length: icbArgumentEncoder.encodedLength) else { return }


        let argumentBuffers: [MTLBuffer] = [argumentEncoder, argumentEncoderAlphaMask, argumentEncoderTransparent]
        let commandBuffers: [MTLIndirectCommandBuffer?] = [commandBuffer, commandBufferAlphaMask, commandBufferTransparent]
        let commandBuffersDepthOnly: [MTLIndirectCommandBuffer?] = [commandBufferDepthOnly, commandBufferDepthOnlyAlphaMask, nil]

        // Encode the buffers
        for (i, argumentBuffer) in argumentBuffers.enumerated() {
            icbArgumentEncoder.setArgumentBuffer(argumentBuffer, offset: 0)
            icbArgumentEncoder.setIndirectCommandBuffer(commandBuffers[i], index: .commandBuffer)
            icbArgumentEncoder.setIndirectCommandBuffer(commandBuffersDepthOnly[i], index: .commandBufferDepthOnly)
        }

        guard let executedCommandsBuffer = device.makeBuffer(length: MemoryLayout<UInt8>.size * totalCommands, options: [.storageModeShared]) else { return }

        // Set the struct to hold onto the icb data
        icb = .init(commandBuffer: commandBuffer,
                    commandBufferAlphaMask: commandBufferAlphaMask,
                    commandBufferTransparent: commandBufferTransparent,
                    commandBufferDepthOnly: commandBufferDepthOnly,
                    commandBufferDepthOnlyAlphaMask: commandBufferDepthOnlyAlphaMask,
                    indirectRangeBuffer: indirectRangeBuffer,
                    indirectRangeCount: indirectRangeCount,
                    argumentEncoder: argumentEncoder,
                    argumentEncoderAlphaMask: argumentEncoderAlphaMask,
                    argumentEncoderTransparent: argumentEncoderTransparent,
                    executedCommandsBuffer: executedCommandsBuffer
        )
    }

    /// Makes the execution range buffer.
    /// - Parameter totalCommands: the total amount of commands the indirect command buffer supports.
    /// - Returns: a new metal buffer with contents of MTLIndirectCommandBufferExecutionRange
    private func makeIndirectRange(_ totalCommands: Int) -> (count: Int, buffer: MTLBuffer?) {

        let rangeCount = Int(ceilf(Float(totalCommands)/Float(maxExecutionRange)))
        var executionRanges: [MTLIndirectCommandBufferExecutionRange] = .init()

        for i in 0..<rangeCount {
            let offset = i * maxExecutionRange
            let commandsInRange = totalCommands - offset
            let length = min(commandsInRange, maxExecutionRange)
            let range = MTLIndirectCommandBufferExecutionRange(location: UInt32(offset), length: UInt32(length))
            executionRanges.append(range)
        }

        let length = MemoryLayout<MTLIndirectCommandBufferExecutionRange>.size * executionRanges.count
        let buffer = device.makeBuffer(bytes: &executionRanges, length: length, options: [.storageModeShared])
        return (executionRanges.count, buffer)
    }
}
