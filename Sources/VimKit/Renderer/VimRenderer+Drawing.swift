//
//  VimRenderer+Drawing.swift
//
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

///  The render encoder label.
private let renderEncoderLabel = "VimRenderEncoder"
///  The render encoder debug group.
private let renderEncoderDebugGroupName = "VimDrawGroup"
///  The minimum amount of instanced meshes to implement frustum culling.
private let minFrustumCullingThreshold = 1024

#if !os(visionOS)

extension VimRenderer: MTKViewDelegate {

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let isLandscape = size.height < size.width
        let aspectRatio = isLandscape ? Float(size.width/size.height) : Float(size.height/size.width)
        context.vim.camera.aspectRatio = aspectRatio
        viewportSize = [Float(size.width), Float(size.height)]
    }

    public func draw(in view: MTKView) {
        renderNewFrame()
    }
}

#endif

public extension VimRenderer {

    /// Renders a new frame.
    private func renderNewFrame() {
        // Prepare the render descriptor
        buildRenderPassDescriptor()
        guard let geometry, geometry.state == .ready else { return }
        guard let renderPassDescriptor,
              let drawable = context.destinationProvider.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        renderEncoder.label = renderEncoderLabel

        // Rotate the uniform buffer address
        updateDynamicBufferState()

        // Update the per-frame uniforms
        updateUniforms()

        // Perform any pre scene draws
        willDrawScene(renderEncoder: renderEncoder)

        // Draw the scene
        drawScene(renderEncoder: renderEncoder)

        // Perform any post scene draws
        didDrawScene(renderEncoder: renderEncoder)

        renderEncoder.endEncoding()

        // Schedule the presentation and commit
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Performs any draws before the scene draw.
    /// - Parameter renderEncoder: the render encoder
    func willDrawScene(renderEncoder: MTLRenderCommandEncoder) {
        guard let geometry,
              let pipelineState,
              let positionsBuffer = geometry.positionsBuffer,
              let normalsBuffer = geometry.normalsBuffer,
              let instancesBuffer = geometry.instancesBuffer,
              let meshesBuffer = geometry.meshesBuffer,
              let submeshesBuffer = geometry.submeshesBuffer,
              let materialsBuffer = geometry.materialsBuffer,
              let colorsBuffer = geometry.colorsBuffer else { return }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(options.cullMode)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setTriangleFillMode(fillMode)

        // Setup the per frame buffers to pass to the GPU
        renderEncoder.setVertexBuffer(uniformBuffer, offset: uniformBufferOffset, index: .uniforms)
        renderEncoder.setVertexBuffer(positionsBuffer, offset: 0, index: .positions)
        renderEncoder.setVertexBuffer(normalsBuffer, offset: 0, index: .normals)
        renderEncoder.setVertexBuffer(instancesBuffer, offset: 0, index: .instances)
        renderEncoder.setVertexBuffer(meshesBuffer, offset: 0, index: .meshes)
        renderEncoder.setVertexBuffer(submeshesBuffer, offset: 0, index: .submeshes)
        renderEncoder.setVertexBuffer(materialsBuffer, offset: 0, index: .materials)
        renderEncoder.setVertexBuffer(colorsBuffer, offset: 0, index: .colors)
        renderEncoder.setFragmentTexture(baseColorTexture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)

        // Set the per frame render options
        var options = RenderOptions(xRay: xRayMode)
        renderEncoder.setVertexBytes(&options, length: MemoryLayout<RenderOptions>.size, index: .renderOptions)
    }

    /// Draws the entire scene.
    /// - Parameter renderEncoder: the render encoder
    func drawScene(renderEncoder: MTLRenderCommandEncoder) {

        guard let geometry else { return }

        renderEncoder.pushDebugGroup(renderEncoderDebugGroupName)

        let results = cullInstancedMeshes(geometry)
        let start = Date.now

        // Draw the instanced meshes
        for i in results {
            guard abs(start.timeIntervalSinceNow) < frameTimeLimit else { break }
            let instanced = geometry.instancedMeshes[i]
            drawInstanced(instanced, renderEncoder: renderEncoder)
        }
        renderEncoder.popDebugGroup()
    }

    /// Performs any draws after the main scene draw.
    /// - Parameter renderEncoder: the render encoder
    func didDrawScene(renderEncoder: MTLRenderCommandEncoder) {
        skycube?.draw(renderEncoder: renderEncoder)
    }

    /// Draws an instanced mesh.
    /// - Parameters:
    ///   - instanced: the instanced mesh to draw
    ///   - renderEncoder: the render encoder
    private func drawInstanced(_ instanced: InstancedMesh, renderEncoder: MTLRenderCommandEncoder) {
        guard let geometry else { return }
        let mesh = geometry.meshes[instanced.mesh]
        let submeshes = geometry.submeshes[mesh.submeshes]
        for (i, submesh) in submeshes.enumerated() {
            let s = mesh.submeshes.range.lowerBound + i
            renderEncoder.pushDebugGroup("SubMesh[\(s)]")

            // Set the identifiers of the mesh + submesh
            var ids = Identifiers(mesh: instanced.mesh, submesh: s)
            renderEncoder.setVertexBytes(&ids, length: MemoryLayout<Identifiers>.size, index: .identifiers)

            // Draw the submesh
            drawSubmesh(geometry, submesh, renderEncoder, instanced.instances.count, instanced.baseInstance)
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

// MARK: Culling

extension VimRenderer {

    /// Culls the instanced meshes that are outside of the view frustum.
    /// - Parameter geometry: the geometry data
    /// - Returns: indices into the geometry.instancedMeshes that should be drawn
    private func cullInstancedMeshes(_ geometry: Geometry) -> Set<Int> {
        guard let bvh = geometry.bvh, minFrustumCullingThreshold <= geometry.instancedMeshes.endIndex else {
            return Set(geometry.instancedMeshes.indices)
        }
        return bvh.intersectionResults(camera: camera)
    }
}
