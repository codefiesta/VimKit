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
private let labelRasterizationRateMap = "RenderRasterizationMap"
private let labelRasterizationRateMapData = "RenderRasterizationMapData"
private let labelDepthPyramidGeneration = "DepthPyramidGeneration"
private let labelTextureDepth = "DepthTexture"
private let labelTextureDepthPyramid = "DepthPyramidTexture"
private let maxBufferBindCount = 24
private let executionRangeCount = 3
private let maxCommandCount = 1024 * 64

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
        /// The icb encodeer arguments buffers consisting of MTLArgumentEncoders
        var argumentEncoder: MTLBuffer
        var argumentEncoderAlphaMask: MTLBuffer
        var argumentEncoderTransparent: MTLBuffer
    }

    /// The context that provides all of the data we need
    let context: RendererContext

    /// The viewport size
    private var screenSize: MTLSize = .zero

    /// The indirect command structure holding the .
    var icb: ICB?

    /// Depth testing
    private var depthPyramid: DepthPyramid?
    private var rasterizationRateMap: MTLRasterizationRateMap?
    private var rasterizationRateMapData: MTLBuffer?
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
        makeRasterizationMap()

        context.vim.geometry?.$state.sink { [weak self] state in
            guard let self, let geometry else { return }
            switch state {
            case .ready:
                debugPrint("􀬨 Building indirect command buffers [\(geometry.instancedMeshes.count)]")
            case .indexing, .loading, .unknown, .error:
                break
            }
        }.store(in: &subscribers)
    }

    /// Performs all encoding and setup options before drawing.
    /// - Parameters:
    ///   - descriptor: the draw descriptor
    func willDraw(descriptor: DrawDescriptor) {

        guard let computeEncoder = descriptor.commandBuffer.makeComputeCommandEncoder() else { return }

        // Encode the buffers onto the comute encoder
        encode(descriptor: descriptor, computeEncoder: computeEncoder)

        // Make the offscreen render pass descriptor
        guard let renderPassDescriptor = makeRenderPassDescriptor(),
              let renderEncoder = descriptor.commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        // Draw the geometry occluder
        drawCulling(descriptor: descriptor, renderEncoder: renderEncoder)

        // End encoding
        renderEncoder.endEncoding()
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
        computeEncoder.setBuffer(icb.executionRange, offset: 0, index: .executionRange)
        computeEncoder.setTexture(depthPyramidTexture, index: 0)

        // 2) Use Resources
        computeEncoder.useResource(icb.commandBuffer, usage: .read)
        computeEncoder.useResource(icb.executionRange, usage: .write)
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

        // 4) End Encoding
        computeEncoder.endEncoding()
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
        renderEncoder.setFragmentBuffer(rasterizationRateMapData, offset: 0, index: .rasterizationRateMapData)
    }

    /// Optimizes the icb.
    /// - Parameters:
    ///   - descriptor: the draw descriptor
    ///   - renderEncoder: the render encoder
    private func optimize(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {

        guard let icb, let geometry else { return }
        guard let blitEncoder = descriptor.commandBuffer.makeBlitCommandEncoder() else { return }
        let range = 0..<geometry.instancedMeshes.count
        blitEncoder.optimizeIndirectCommandBuffer(icb.commandBuffer, range: range)
        blitEncoder.endEncoding()
    }

    /// Performs the indirect drawing via icb.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func drawIndirect(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {
        guard let icb else { return }
        let offset = MemoryLayout<MTLIndirectCommandBufferExecutionRange>.size * 0
        renderEncoder.executeCommandsInBuffer(icb.commandBuffer, indirectBuffer: icb.executionRange, offset: offset)
    }

    private func drawCulling(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {

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

        guard let blitEncoder = descriptor.commandBuffer.makeBlitCommandEncoder() else { return }
        blitEncoder.resetCommandsInBuffer(icb.commandBuffer, range: 0..<geometry.instancedMeshes.count)
        blitEncoder.endEncoding()
    }

    /// Default resize function
    /// - Parameter viewportSize: the new viewport size
    func resize(viewportSize: SIMD2<Float>) {
        screenSize = MTLSize(width: Int(viewportSize.x), height: Int(viewportSize.y), depth: .zero)
        makeTextures()
        makeRasterizationMap()
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

    private func makeIndirectCommandBuffers() {

        guard let computeFunction else { return }

        // Make the indirect command buffer descriptor
        let descriptor = MTLIndirectCommandBufferDescriptor()
        descriptor.commandTypes = [.drawIndexed]
        descriptor.inheritBuffers = false
        descriptor.inheritPipelineState = true
        descriptor.maxVertexBufferBindCount = maxBufferBindCount
        descriptor.maxFragmentBufferBindCount = maxBufferBindCount

        // Make the indirect command buffers and label them
        guard let commandBuffer = device.makeIndirectCommandBuffer(descriptor: descriptor, maxCommandCount: maxCommandCount),
              let commandBufferAlphaMask = device.makeIndirectCommandBuffer(descriptor: descriptor, maxCommandCount: maxCommandCount),
              let commandBufferTransparent = device.makeIndirectCommandBuffer(descriptor: descriptor, maxCommandCount: maxCommandCount),
              let commandBufferDepthOnly = device.makeIndirectCommandBuffer(descriptor: descriptor, maxCommandCount: maxCommandCount),
              let commandBufferDepthOnlyAlphaMask = device.makeIndirectCommandBuffer(descriptor: descriptor, maxCommandCount: maxCommandCount) else { return }

        commandBuffer.label = labelICB
        commandBufferAlphaMask.label = labelICBAlphaMask
        commandBufferTransparent.label = labelICBTransparent
        commandBufferDepthOnly.label = labelICBDepthOnly
        commandBufferDepthOnlyAlphaMask.label = labelICBDepthOnlyAlphaMask

        // Make the execution range buffer
        guard let executionRange = makeExecutionRange() else { return }

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

        // Set the struct to hold onto the icb data
        icb = .init(commandBuffer: commandBuffer,
                    commandBufferAlphaMask: commandBufferAlphaMask,
                    commandBufferTransparent: commandBufferTransparent,
                    commandBufferDepthOnly: commandBufferDepthOnly,
                    commandBufferDepthOnlyAlphaMask: commandBufferDepthOnlyAlphaMask,
                    executionRange: executionRange,
                    argumentEncoder: argumentEncoder,
                    argumentEncoderAlphaMask: argumentEncoderAlphaMask,
                    argumentEncoderTransparent: argumentEncoderTransparent)
    }

    /// Rebuilds the depth textures
    private func makeTextures() {
        guard screenSize != .zero else { return }

        let width = Int(screenSize.width)
        let height = Int(screenSize.height)

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
            pixelFormat: .depth32Float,
            width: width / 2,
            height: height / 2,
            mipmapped: true)
        depthPyramidTextureDescriptor.storageMode = .private
        depthPyramidTextureDescriptor.usage = [.shaderRead, .shaderWrite, .pixelFormatView]
        depthPyramidTexture = device.makeTexture(descriptor: depthPyramidTextureDescriptor)
        depthPyramidTexture?.label = labelTextureDepthPyramid
    }

    private func makeRasterizationMap() {

        guard screenSize != .zero else { return }
        let quality: [Float] = [0.3, 0.6, 1.0, 0.6, 0.3]
        let sampleCount: MTLSize = .init(width: 5, height: 5, depth: 0)
        let layerDescriptor: MTLRasterizationRateLayerDescriptor = .init(horizontal: quality, vertical: quality)
        layerDescriptor.sampleCount = sampleCount

        let rasterizationRateMapDescriptor: MTLRasterizationRateMapDescriptor = .init(screenSize: screenSize, layer: layerDescriptor, label: labelRasterizationRateMap)

        guard let rasterizationRateMap = device.makeRasterizationRateMap(descriptor: rasterizationRateMapDescriptor) else { return }

        self.rasterizationRateMap = rasterizationRateMap
        let bufferLength = rasterizationRateMap.parameterDataSizeAndAlign.size
        guard let rasterizationRateMapData = device.makeBuffer(length: bufferLength, options: []) else { return }
        rasterizationRateMapData.label = labelRasterizationRateMapData

        self.rasterizationRateMapData = rasterizationRateMapData
        rasterizationRateMap.copyParameterData(buffer: rasterizationRateMapData, offset: 0)
    }

    /// Builds an offscreen render pass descriptor.
    private func makeRenderPassDescriptor() -> MTLRenderPassDescriptor? {

        let renderPassDescriptor = MTLRenderPassDescriptor()

        // Depth attachment
        renderPassDescriptor.depthAttachment.texture = depthTexture
        renderPassDescriptor.depthAttachment.clearDepth = 1.0
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .store
        renderPassDescriptor.rasterizationRateMap = rasterizationRateMap
        return renderPassDescriptor
    }

    private func makeExecutionRange(_ totalCommands: Int = maxCommandCount) -> MTLBuffer? {

        //        guard let executionRange = device.makeBuffer(length: MemoryLayout<MTLIndirectCommandBufferExecutionRange>.size * executionRangeCount,
        //                                                     options: [.storageModeShared]) else { return }
        let rangeCount = Int(ceilf(Float(totalCommands)/Float(maxCommandCount)))
        var ranges: [Range<Int>] = .init()
        for i in 0..<rangeCount {
            let start = i * maxCommandCount
            let end = min(start + maxCommandCount, totalCommands)
            let range = start..<end

            ranges.append(range)
        }

        var executionRanges = ranges.map {
            MTLIndirectCommandBufferExecutionRange(location: UInt32($0.lowerBound), length: UInt32($0.upperBound))
        }

        // 16384
        let length = MemoryLayout<MTLIndirectCommandBufferExecutionRange>.size * executionRanges.count
        return device.makeBuffer(bytes: &executionRanges, length: length, options: [.storageModeShared])
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

        var src: MTLTexture? = depthTexture
        var startMip = 0

        if depthPyramidTexture.label == depthTexture.label {
            let range = 0..<1
            src = depthPyramidTexture.makeTextureView(pixelFormat: .r32Float, textureType: .type2D, levels: range, slices: range)
            startMip = 1
        }

        guard let src else { return }

        for i in startMip..<depthPyramidTexture.mipmapLevelCount {

            let levels = i..<1
            let slices = 0..<1

            guard let dest = depthPyramidTexture.makeTextureView(pixelFormat: .r32Float,
                                                                 textureType: .type2D,
                                                                 levels: levels,
                                                                 slices: slices) else { continue }
            dest.label = "PyramidMip\(i)"
            encoder.setTexture(src, index: 0)
            encoder.setTexture(dest, index: 1)

            var sizes: SIMD4<UInt> = [UInt(src.width), UInt(src.height), .zero, .zero]
            encoder.setBytes(&sizes, length: MemoryLayout<SIMD4<UInt>>.size, index: .depthPyramidSize)

            let threadsPerThreadgroup: MTLSize = .init(width: 8, height: 8, depth: 1)
            let threadsPerGrid: MTLSize = .init(width: dest.width, height: dest.height, depth: 1)
                .divideRoundUp(threadsPerThreadgroup)
            encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
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
