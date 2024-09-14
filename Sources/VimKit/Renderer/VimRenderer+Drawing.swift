//
//  VimRenderer+Drawing.swift
//
//
//  Created by Kevin McKee
//

import MetalKit
import SwiftUI
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

        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { (_) in
            semaphore.signal()
        }

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
              let instancesBuffer = geometry.instancesBuffer else { return }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFrontFacing(.clockwise)
        renderEncoder.setCullMode(.none)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setTriangleFillMode(fillMode)

        // Setup the per frame buffers to pass to the GPU
        renderEncoder.setVertexBuffer(uniformBuffer, offset: uniformBufferOffset, index: .uniforms)
        renderEncoder.setVertexBuffer(positionsBuffer, offset: 0, index: .positions)
        renderEncoder.setVertexBuffer(normalsBuffer, offset: 0, index: .normals)
        renderEncoder.setVertexBuffer(instancesBuffer, offset: 0, index: .instances)
        renderEncoder.setFragmentTexture(baseColorTexture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)

        // Set xRay mode
        var xRay = xRayMode
        renderEncoder.setVertexBytes(&xRay, length: MemoryLayout<Bool>.size, index: .xRay)

        // Set the override color (for selection or highlighting)
        var color = Color.objectSelectionColor.channels
        renderEncoder.setVertexBytes(&color, length: MemoryLayout<SIMD4<Float>>.size, index: .colorOverride)
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

        // Draw the shapes
        shapes?.draw(renderEncoder: renderEncoder)
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
    private func drawInstanced(_ instanced: Geometry.InstancedMesh, renderEncoder: MTLRenderCommandEncoder) {
        guard let geometry, let range = instanced.mesh.submeshes else { return }

        let submeshes = geometry.submeshes[range]
        for (i, submesh) in submeshes.enumerated() {
            guard let material = submesh.material, material.rgba.w > .zero else { continue }
            renderEncoder.pushDebugGroup("SubMesh[\(i)]")

            // Set the mesh uniforms
            var uniforms = meshUniforms(submesh: submesh)
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<MeshUniforms>.size, index: .meshUniforms)

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
                             _ submesh: Geometry.Submesh,
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

// MARK: Per Mesh Uniforms

extension VimRenderer {

    /// Returns the per mesh uniforms for the specifed submesh.
    /// - Parameters:
    ///   - submesh: the submesh
    /// - Returns: the mesh unifroms
    func meshUniforms(submesh: Geometry.Submesh) -> MeshUniforms {
        return MeshUniforms(
            color: submesh.material?.rgba ?? .zero,
            glossiness: submesh.material?.glossiness ?? .half,
            smoothness: submesh.material?.smoothness ?? .half
        )
    }
}

// MARK: Culling

extension VimRenderer {

    /// Culls the instanced meshes that are outside of the view frustum.
    /// - Parameter geometry: the geometry data
    /// - Returns: indices into the geometry.instancedMeshes that should be drawn
    private func cullInstancedMeshes(_ geometry: Geometry) -> [Int] {
        guard let bvh = geometry.bvh, minFrustumCullingThreshold <= geometry.instancedMeshes.endIndex else {
            return Array(geometry.instancedMeshes.indices)
        }
        return bvh.intersectionResults(camera: camera)
    }
}
