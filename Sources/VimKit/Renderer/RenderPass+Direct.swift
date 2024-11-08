//
//  RenderPass+Direct.swift
//  VimKit
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

private let functionNameVertex = "vertexMain"
private let functionNameFragment = "fragmentMain"
private let labelInstancePickingTexture = "InstancePickingTexture"
private let labelPipeline = "RenderPassDirectPipeline"
private let labelRenderEncoder = "RenderEncoderDirect"
private let labelGeometryDebugGroupName = "Geometry"

/// Provides a direct render pass.
class RenderPassDirect: RenderPass {

    /// The context that provides all of the data we need
    let context: RendererContext

    var pipelineState: MTLRenderPipelineState?
    var depthStencilState: MTLDepthStencilState?
    var samplerState: MTLSamplerState?

    /// The max time to render a frame.
    var frameTimeLimit: TimeInterval = 0.3

    /// Initializes the render pass with the provided rendering context.
    /// - Parameter context: the rendering context.
    init(_ context: RendererContext) {
        self.context = context
        let vertexDescriptor = makeVertexDescriptor()
        self.pipelineState = makeRenderPipelineState(context, vertexDescriptor, labelPipeline, functionNameVertex, functionNameFragment)
        self.depthStencilState = makeDepthStencilState()
        self.samplerState = makeSamplerState()
    }

    /// Performs a draw call with the specified command buffer and render pass descriptor.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    func draw(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {

        // Encode the buffers
        encode(descriptor: descriptor, renderEncoder: renderEncoder)

        // Make the draw calls
        drawGeometry(descriptor: descriptor, renderEncoder: renderEncoder)
    }

    /// Encodes the buffer data into the render encoder.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func encode(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {
        guard let geometry,
              let pipelineState,
              let positionsBuffer = geometry.positionsBuffer,
              let normalsBuffer = geometry.normalsBuffer,
              let instancesBuffer = geometry.instancesBuffer,
              let submeshesBuffer = geometry.submeshesBuffer,
              let colorsBuffer = geometry.colorsBuffer else { return }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(options.cullMode)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setTriangleFillMode(fillMode)

        // Setup the per frame buffers to pass to the GPU
        renderEncoder.setVertexBuffer(descriptor.uniformsBuffer, offset: descriptor.uniformsBufferOffset, index: .uniforms)
        renderEncoder.setVertexBuffer(positionsBuffer, offset: 0, index: .positions)
        renderEncoder.setVertexBuffer(normalsBuffer, offset: 0, index: .normals)
        renderEncoder.setVertexBuffer(instancesBuffer, offset: 0, index: .instances)
        renderEncoder.setVertexBuffer(submeshesBuffer, offset: 0, index: .submeshes)
        renderEncoder.setVertexBuffer(colorsBuffer, offset: 0, index: .colors)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)

        // Set the per frame render options
        var options = RenderOptions(xRay: xRayMode)
        renderEncoder.setVertexBytes(&options, length: MemoryLayout<RenderOptions>.size, index: .renderOptions)

    }

    /// Draws all visible geometry.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func drawGeometry(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {

        guard let geometry else { return }

        renderEncoder.pushDebugGroup(labelGeometryDebugGroupName)

        let start = Date.now

        // Draw the instanced meshes
        for i in descriptor.visibilityResults {
            guard abs(start.timeIntervalSinceNow) < frameTimeLimit else { break }
            let instanced = geometry.instancedMeshes[i]
            drawInstanced(instanced, renderEncoder: renderEncoder)
        }
        renderEncoder.popDebugGroup()
    }


    /// Draws an instanced mesh.
    /// - Parameters:
    ///   - instanced: the instanced mesh to draw
    ///   - renderEncoder: the render encoder
    private func drawInstanced(_ instanced: InstancedMesh, renderEncoder: MTLRenderCommandEncoder) {
        guard let geometry, let materialsBuffer = geometry.materialsBuffer else { return }
        let mesh = geometry.meshes[instanced.mesh]
        let submeshes = geometry.submeshes[mesh.submeshes]
        for (i, submesh) in submeshes.enumerated() {
            renderEncoder.pushDebugGroup("SubMesh[\(i)]")

            let offset = submesh.material * MemoryLayout<Material>.stride
            renderEncoder.setVertexBuffer(materialsBuffer, offset: offset, index: .materials)

            // Draw the submesh
            drawSubmesh(geometry, submesh, renderEncoder, instanced.instanceCount, instanced.baseInstance)
            renderEncoder.popDebugGroup()
        }
    }

    /// Draws the submesh using indexed primitives.
    /// - Parameters:
    ///   - geometry: the geometry
    ///   - submesh: the submesh
    ///   - renderEncoder: the render encoder to use
    ///   - instanceCount: the number of instances to draw.
    ///   - baseInstance: the offset for instance_id
    private func drawSubmesh(_ geometry: Geometry,
                             _ submesh: Submesh,
                             _ renderEncoder: MTLRenderCommandEncoder,
                             _ instanceCount: Int = 1,
                             _ baseInstance: Int = 0) {

        guard let indexBuffer = geometry.indexBuffer else { return }
        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: submesh.indices.count,
                                            indexType: .uint32,
                                            indexBuffer: indexBuffer,
                                            indexBufferOffset: submesh.indexBufferOffset,
                                            instanceCount: instanceCount,
                                            baseVertex: 0,
                                            baseInstance: baseInstance
        )
    }
}
