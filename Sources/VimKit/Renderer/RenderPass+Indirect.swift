//
//  RenderPass+Indirect.swift
//  VimKit
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

private let functionNameVertex = "vertexMain"
private let functionNameFragment = "fragmentMain"
private let functionNameEncodeIndirectCommands = "encodeIndirectCommands"
private let functionNameDepthPyramid = "depthPyramid"
private let labelICB = "VimIndirectCommandBuffer"
private let labelPipeline = "VimRendererPipeline"
private let labelRenderEncoder = "RenderEncoderIndirect"
private let labelRasterizationRateMap = "RenderRasterizationMap"
private let labelRasterizationRateMapData = "RenderRasterizationMapData"
private let labelDepthPyramidGeneration = "DepthPyramidGeneration"
private let maxCommandCount = 1024 * 64
private let maxBufferBindCount = 24

/// Provides an indirect render pass using indirect command buffers.
class RenderPassIndirect: RenderPass {

    /// The context that provides all of the data we need
    let context: RendererContext

    /// The viewport size
    private var screenSize: MTLSize = .zero

    /// The compute pipeline state.
    private var computePipelineState: MTLComputePipelineState?
    /// The indirect command buffer to use to issue visibility results.
    private var icb: MTLIndirectCommandBuffer?
    /// Argument buffer containing the indirect command buffer encoded in the kernel
    private var icbBuffer: MTLBuffer?

    /// Depth testing
    private var depthPyramid: DepthPyramid?
    private var rasterizationRateMap: MTLRasterizationRateMap?
    private var rasterizationRateMapData: MTLBuffer?
    private var depthPyramidTexture: MTLTexture?

    private var pipelineState: MTLRenderPipelineState?
    private var depthStencilState: MTLDepthStencilState?
    private var samplerState: MTLSamplerState?

    /// Initializes the render pass with the provided rendering context.
    /// - Parameter context: the rendering context.
    init?(_ context: RendererContext) {
        self.context = context
        guard let library = makeLibrary() else { return nil }

        let vertexDescriptor = makeVertexDescriptor()
        self.pipelineState = makeRenderPipelineState(context, vertexDescriptor, labelPipeline, functionNameVertex, functionNameFragment)
        self.depthStencilState = makeDepthStencilState()
        self.samplerState = makeSamplerState()
        self.depthPyramid = DepthPyramid(device, library)
        makeComputePipelineState(library)
        makeRasterizationMap()
    }

    /// Performs all encoding and setup options before drawing.
    /// - Parameters:
    ///   - descriptor: the draw descriptor
    func willDraw(descriptor: DrawDescriptor) {

        guard let geometry,
              let computePipelineState,
              let icb,
              let icbBuffer,
              let uniformsBuffer = descriptor.uniformsBuffer,
              let positionsBuffer = geometry.positionsBuffer,
              let normalsBuffer = geometry.normalsBuffer,
              let indexBuffer = geometry.indexBuffer,
              let instancesBuffer = geometry.instancesBuffer,
              let instancedMeshesBuffer = geometry.instancedMeshesBuffer,
              let meshesBuffer = geometry.meshesBuffer,
              let submeshesBuffer = geometry.submeshesBuffer,
              let materialsBuffer = geometry.materialsBuffer,
              let colorsBuffer = geometry.colorsBuffer,
              let computeEncoder = descriptor.commandBuffer.makeComputeCommandEncoder() else { return }

        var options = RenderOptions(xRay: xRayMode)

        // 1) Encode
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setBuffer(uniformsBuffer, offset: descriptor.uniformsBufferOffset, index: .uniforms)
        computeEncoder.setBuffer(positionsBuffer, offset: 0, index: .positions)
        computeEncoder.setBuffer(normalsBuffer, offset: 0, index: .normals)
        computeEncoder.setBuffer(indexBuffer, offset: 0, index: .indexBuffer)
        computeEncoder.setBuffer(instancesBuffer, offset: 0, index: .instances)
        computeEncoder.setBuffer(instancedMeshesBuffer, offset: 0, index: .instancedMeshes)
        computeEncoder.setBuffer(meshesBuffer, offset: 0, index: .meshes)
        computeEncoder.setBuffer(submeshesBuffer, offset: 0, index: .submeshes)
        computeEncoder.setBuffer(materialsBuffer, offset: 0, index: .materials)
        computeEncoder.setBuffer(colorsBuffer, offset: 0, index: .colors)
        computeEncoder.setBuffer(icbBuffer, offset: 0, index: .commandBufferContainer)
        computeEncoder.setBytes(&options, length: MemoryLayout<RenderOptions>.size, index: .renderOptions)
        computeEncoder.setTexture(depthPyramidTexture, index: 0)

        // 2) Use Resources
        computeEncoder.useResource(icb, usage: .read)
        computeEncoder.useResource(uniformsBuffer, usage: .read)
        computeEncoder.useResource(materialsBuffer, usage: .read)
        computeEncoder.useResource(instancesBuffer, usage: .read)
        computeEncoder.useResource(instancedMeshesBuffer, usage: .read)
        computeEncoder.useResource(meshesBuffer, usage: .read)
        computeEncoder.useResource(submeshesBuffer, usage: .read)
        computeEncoder.useResource(meshesBuffer, usage: .read)
        computeEncoder.useResource(indexBuffer, usage: .read)

        // 3) Dispatch the threads
        let drawCount = geometry.instancedMeshes.count
        let gridSize: MTLSize = .init(width: drawCount, height: 1, depth: 1)
        let threadExecutionWidth = computePipelineState.threadExecutionWidth
        let threadgroupSize: MTLSize = .init(width: threadExecutionWidth, height: 1, depth: 1)
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)

        // 4) End Encoding
        computeEncoder.endEncoding()
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

    /// Performs the indirect drawing via icb.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func drawIndirect(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {
        guard let geometry, let icb else { return }

        // Build the range of commands to execute
        let range = 0..<geometry.instancedMeshes.count

        // Execute the commands in range
        renderEncoder.executeCommandsInBuffer(icb, range: range)
    }

    /// Makes the compute pipeline state.
    /// - Parameter library: the metal library
    private func makeComputePipelineState(_ library: MTLLibrary) {

        guard supportsIndirectCommandBuffers else {
            debugPrint("💩 Indirect command buffers are not supported on this device.")
            return
        }

        let descriptor = MTLIndirectCommandBufferDescriptor()
        descriptor.commandTypes = [.drawIndexed]
        descriptor.inheritBuffers = false
        descriptor.inheritPipelineState = true
        descriptor.maxVertexBufferBindCount = maxBufferBindCount
        descriptor.maxFragmentBufferBindCount = maxBufferBindCount

        // Create icb using private storage mode since only the GPU will read+write to/from buffer
        guard let function = library.makeFunction(name: functionNameEncodeIndirectCommands),
              let computePipelineState = try? device.makeComputePipelineState(function: function),
              let icb = device.makeIndirectCommandBuffer(descriptor: descriptor,
                                                         maxCommandCount: maxCommandCount,
                                                         options: []) else { return }

        icb.label = labelICB
        self.icb = icb
        self.computePipelineState = computePipelineState

        let icbEncoder = function.makeArgumentEncoder(.commandBufferContainer)
        icbBuffer = device.makeBuffer(length: icbEncoder.encodedLength, options: [])
        icbEncoder.setArgumentBuffer(icbBuffer, offset: 0)
        icbEncoder.setIndirectCommandBuffer(icb, index: .commandBuffer)
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

    /// Default resize function
    /// - Parameter viewportSize: the new viewport size
    func resize(viewportSize: SIMD2<Float>) {
        screenSize = MTLSize(width: Int(viewportSize.x), height: Int(viewportSize.y), depth: .zero)
        makeRasterizationMap()
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
