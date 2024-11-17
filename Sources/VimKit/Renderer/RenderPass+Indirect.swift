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

    /// A container that holds all of the
    struct ICB {
        /// The default indirect command buffers
        var commandBuffer: MTLIndirectCommandBuffer
        var commandBufferAlphaMask: MTLIndirectCommandBuffer
        var commandBufferTransparent: MTLIndirectCommandBuffer
        /// The indirect command buffers used for depth only
        var commandBufferDepthOnly: MTLIndirectCommandBuffer
        var commandBufferDepthOnlyAlphaMask: MTLIndirectCommandBuffer
        /// A metal buffer storing the icb execution range
        var executionRange: MTLBuffer
        /// The number of execution ranges.
        var executionRangeCount: Int
        /// The icb encodeer arguments buffers consisting of MTLArgumentEncoders
        var argumentEncoder: MTLBuffer
        var argumentEncoderAlphaMask: MTLBuffer
        var argumentEncoderTransparent: MTLBuffer
        /// A metal buffer for keep track of executed commands storing a single byte per command.
        var executedCommandsBuffer: MTLBuffer?
    }

    /// The context that provides all of the data we need
    let context: RendererContext

    /// The indirect command structure holding the .
    var icb: ICB?

    /// Depth testing
    private var depthPyramid: DepthPyramid?
    private var depthTexture: MTLTexture?
    private var depthPyramidTexture: MTLTexture?

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
        self.depthPyramid = DepthPyramid(device, library)
        makeComputePipelineState(library)
        makeIndirectCommandBuffers()

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

        guard let depthPyramid,
              let depthPyramidTexture,
              let depthTexture,
              let computeEncoder = descriptor.commandBuffer.makeComputeCommandEncoder() else { return }

        // Generate the depth pyramid
        depthPyramid.generate(depthPyramidTexture: depthPyramidTexture, depthTexture: depthTexture, encoder: computeEncoder)

        // Encode the buffers onto the comute encoder
        encode(descriptor: descriptor, computeEncoder: computeEncoder)

        // End the compute encoding
        computeEncoder.endEncoding()

        // Make the offscreen render pass descriptor
        guard let renderPassDescriptor = makeRenderPassDescriptor(descriptor: descriptor),
              let renderEncoder = descriptor.commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        // Draw the geometry occluder offscreen
        drawDepthOffscreen(descriptor: descriptor, renderEncoder: renderEncoder)

        // End encoding
        renderEncoder.endEncoding()

        // Reset
        reset(descriptor: descriptor);
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
        computeEncoder.setBuffer(descriptor.rasterizationRateMapData, offset: 0, index: .rasterizationRateMapData)
        computeEncoder.setTexture(depthPyramidTexture, index: 0)

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

        // 3) Dispatch the threads
        let gridSize = geometry.gridSize
        let width = computePipelineState.threadExecutionWidth
        let height = computePipelineState.maxTotalThreadsPerThreadgroup / width
        let threadgroupSize: MTLSize = .init(width: width, height: height, depth: 1)
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
        renderEncoder.setFragmentBuffer(descriptor.rasterizationRateMapData, offset: 0, index: .rasterizationRateMapData)
    }

    /// Resets the commands in the indirect command buffer.
    /// - Parameters:
    ///   - descriptor: the draw descriptor
    ///   - renderEncoder: the render encoder
    private func reset(descriptor: DrawDescriptor) {
        guard let icb, let geometry else { return }
        let gridSize = geometry.gridSize
        let totalCommands = gridSize.width * gridSize.height

        if let executedCommandsBuffer = icb.executedCommandsBuffer {
            Task {
                let range: UnsafeMutableBufferPointer<UInt8> = executedCommandsBuffer.toUnsafeMutableBufferPointer()
                let count = range.filter{ $0 == 1 }.count
                context.vim.stats.executedCommands = count
            }
        }
    }

    /// Optimizes the icb.
    /// - Parameters:
    ///   - descriptor: the draw descriptor
    private func optimize(descriptor: DrawDescriptor) {
        guard let icb, let geometry, let blitEncoder = descriptor.commandBuffer.makeBlitCommandEncoder() else { return }
        let gridSize = geometry.gridSize
        let range = 0..<gridSize.width * gridSize.height
        blitEncoder.optimizeIndirectCommandBuffer(icb.commandBuffer, range: range)
        blitEncoder.endEncoding()
    }

    /// Performs the indirect drawing via icb.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func drawIndirect(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {
        guard let icb else { return }
        for i in 0..<icb.executionRangeCount {
            let offset = MemoryLayout<MTLIndirectCommandBufferExecutionRange>.size * i
            renderEncoder.executeCommandsInBuffer(icb.commandBuffer, indirectBuffer: icb.executionRange, offset: offset)
        }
    }

    /// Draws the depth pyramid offscreen.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func drawDepthOffscreen(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {

        guard let geometry,
              let icb,
              let pipelineStateDepthOnly,
              let positionsBuffer = geometry.positionsBuffer,
              let indexBuffer = geometry.indexBuffer else { return }

        renderEncoder.setRenderPipelineState(pipelineStateDepthOnly)
        renderEncoder.setDepthStencilState(depthStencilState)
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

    /// Default resize function
    /// - Parameters:
    ///   - viewportSize: the viewport size
    ///   - physicalSize: the physical size
    func resize(viewportSize: SIMD2<Float>, physicalSize: SIMD2<Float>) {
        makeTextures(physicalSize)
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
        let executionRangeResult = makeExecutionRange(totalCommands)
        guard let executionRange = executionRangeResult.buffer else { return }
        let executionRangeCount = executionRangeResult.count

        // Make the argument encoders
        let icbArgumentEncoder = computeFunction.makeArgumentEncoder(.commandBufferContainer)
        guard let argumentEncoder = device.makeBuffer(length: icbArgumentEncoder.encodedLength),
              let argumentEncoderAlphaMask = device.makeBuffer(length: icbArgumentEncoder.encodedLength),
              let argumentEncoderTransparent = device.makeBuffer(length: icbArgumentEncoder.encodedLength) else { return }


        var argumentBuffers: [MTLBuffer] = [argumentEncoder, argumentEncoderAlphaMask, argumentEncoderTransparent]
        var commandBuffers: [MTLIndirectCommandBuffer?] = [commandBuffer, commandBufferAlphaMask, commandBufferTransparent]
        var commandBuffersDepthOnly: [MTLIndirectCommandBuffer?] = [commandBufferDepthOnly, commandBufferDepthOnlyAlphaMask, nil]

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
                    executionRange: executionRange,
                    executionRangeCount: executionRangeCount,
                    argumentEncoder: argumentEncoder,
                    argumentEncoderAlphaMask: argumentEncoderAlphaMask,
                    argumentEncoderTransparent: argumentEncoderTransparent,
                    executedCommandsBuffer: executedCommandsBuffer
        )
    }

    /// Makes the depth textures.
    private func makeTextures(_ physicalSize: SIMD2<Float>) {
        guard physicalSize != .zero else { return }

        let width = Int(physicalSize.x)
        let height = Int(physicalSize.y)

        // Depth Texture
        let depthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false)
        depthTextureDescriptor.storageMode = .private
        depthTextureDescriptor.usage = [.renderTarget, .shaderRead]

        depthTexture = device.makeTexture(descriptor: depthTextureDescriptor)
        depthTexture?.label = labelTextureDepth

        // Depth Pyramid Texture
        let depthPyramidTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: width / 2,
            height: height / 2,
            mipmapped: true)
        depthPyramidTextureDescriptor.storageMode = .private
        depthPyramidTextureDescriptor.usage = [.shaderRead, .shaderWrite, .pixelFormatView]
        depthPyramidTexture = device.makeTexture(descriptor: depthPyramidTextureDescriptor)
        depthPyramidTexture?.label = labelTextureDepthPyramid
    }

    /// Builds an offscreen render pass descriptor.
    /// - Returns: the offscreen render pass descriptor
    private func makeRenderPassDescriptor(descriptor: DrawDescriptor) -> MTLRenderPassDescriptor? {

        let renderPassDescriptor = MTLRenderPassDescriptor()

        // Depth attachment
        renderPassDescriptor.depthAttachment.texture = depthTexture
        renderPassDescriptor.depthAttachment.clearDepth = 1.0
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .store
        renderPassDescriptor.rasterizationRateMap = descriptor.rasterizationRateMap
        return renderPassDescriptor
    }

    /// Makes the execution range buffer.
    /// - Parameter totalCommands: the total amount of commands the indirect command buffer supports.
    /// - Returns: a new metal buffer cf MTLIndirectCommandBufferExecutionRange
    private func makeExecutionRange(_ totalCommands: Int) -> (count: Int, buffer: MTLBuffer?) {

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

@MainActor
fileprivate class DepthPyramid {

    private let device: MTLDevice

    /// The compute pipeline state.
    var computePipelineState: MTLComputePipelineState?

    init?(_ device: MTLDevice, _ library: MTLLibrary) {
        self.device = device
        self.computePipelineState = makeComputePipelineState(library)
    }

    /// Generates the depth pyramid texture from the specified depth texture.
    /// Supports both being the same texture.
    /// - Parameters:
    ///   - depthPyramidTexture: the depth pyramid texture.
    ///   - depthTexture: the depth texture.
    ///   - encoder: the encoder to use.
    func generate(depthPyramidTexture: MTLTexture, depthTexture: MTLTexture, encoder: MTLComputeCommandEncoder ) {
        guard let computePipelineState else { return }

        encoder.pushDebugGroup(labelDepthPyramidGeneration)
        encoder.setComputePipelineState(computePipelineState)

        var srcTexture: MTLTexture? = depthTexture
        var startMip = 0

        if depthPyramidTexture.label == depthTexture.label {
            let levels = 0..<1
            let slices = 0..<1
            srcTexture = depthPyramidTexture.makeTextureView(pixelFormat: .r32Float, textureType: .type2D, levels: levels, slices: slices)
            startMip = 1
        }

        guard let srcTexture else { return }

        for i in startMip..<depthPyramidTexture.mipmapLevelCount {

            let levels: Range<Int> = i..<i+1
            let slices: Range<Int> = 0..<1

            guard let destinationTexture = depthPyramidTexture.makeTextureView(pixelFormat: .r32Float,
                                                                 textureType: .type2D,
                                                                 levels: levels,
                                                                 slices: slices) else { continue }
            encoder.setTexture(srcTexture, index: 0)
            encoder.setTexture(destinationTexture, index: 1)
            encoder.useResource(destinationTexture, usage: .write)

            var sizes: SIMD4<UInt> = [UInt(srcTexture.width), UInt(srcTexture.height), .zero, .zero]
            encoder.setBytes(&sizes, length: MemoryLayout<SIMD4<UInt>>.size, index: .depthPyramidSize)

            let threadsPerThreadgroup: MTLSize = .init(width: 8, height: 8, depth: 1)

            let gridSize: MTLSize = .init(width: destinationTexture.width, height: destinationTexture.height, depth: 1)
                .divideRoundUp(threadsPerThreadgroup)

            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerThreadgroup)
        }
        encoder.popDebugGroup()
    }

    /// Makes the compute pipeline state.
    /// - Parameter library: the metal library
    private func makeComputePipelineState(_ library: MTLLibrary) -> MTLComputePipelineState? {
        guard let function = library.makeFunction(name: functionNameDepthPyramid) else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }
}
