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
private let labelICB = "VimIndirectCommandBuffer"
private let labelPipeline = "VimRendererPipeline"
private let labelRenderEncoder = "RenderEncoderIndirect"
private let maxCommandCount = 1024 * 64
private let maxBufferBindCount = 24

/// Provides an indirect render pass using indirect command buffers.
class RenderPassIndirect: RenderPass {

    /// The context that provides all of the data we need
    let context: RendererContext

    /// The compute pipeline state.
    var computePipelineState: MTLComputePipelineState?
    /// The indirect command buffer to use to issue visibility results.
    var icb: MTLIndirectCommandBuffer?
    /// Argument buffer containing the indirect command buffer encoded in the kernel
    var icbBuffer: MTLBuffer?

    var pipelineState: MTLRenderPipelineState?
    var depthStencilState: MTLDepthStencilState?
    var samplerState: MTLSamplerState?

    /// Initializes the render pass with the provided rendering context.
    /// - Parameter context: the rendering context.
    init?(_ context: RendererContext) {
        self.context = context
        guard let library = makeLibrary() else { return nil }

        let vertexDescriptor = makeVertexDescriptor()
        self.pipelineState = makeRenderPipelineState(context, vertexDescriptor, labelPipeline, functionNameVertex, functionNameFragment)
        self.depthStencilState = makeDepthStencilState()
        self.samplerState = makeSamplerState()

        makeComputePipelineState(library)
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
              let visibilityResultBuffer = descriptor.visibilityResultBuffer,
              let computeEncoder = descriptor.commandBuffer.makeComputeCommandEncoder() else { return }

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
        computeEncoder.setBuffer(visibilityResultBuffer, offset: 0, index: .visibilityResults)
        computeEncoder.setBuffer(icbBuffer, offset: 0, index: .commandBufferContainer)

        var options = RenderOptions(xRay: xRayMode)
        computeEncoder.setBytes(&options, length: MemoryLayout<RenderOptions>.size, index: .renderOptions)

        // 2) Use Resources
        computeEncoder.useResource(icb, usage: .write)
        computeEncoder.useResource(uniformsBuffer, usage: .read)
        computeEncoder.useResource(visibilityResultBuffer, usage: .read)
        computeEncoder.useResource(materialsBuffer, usage: .read)
        computeEncoder.useResource(instancesBuffer, usage: .read)
        computeEncoder.useResource(instancedMeshesBuffer, usage: .read)
        computeEncoder.useResource(meshesBuffer, usage: .read)
        computeEncoder.useResource(submeshesBuffer, usage: .read)
        computeEncoder.useResource(meshesBuffer, usage: .read)
        computeEncoder.useResource(indexBuffer, usage: .write)

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
    }

    /// Performs the indirect drawing via icb.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func drawIndirect(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {
        guard let geometry,
              let icb else { return }

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
}
