//
//  VimRenderer+Drawing.swift
//
//
//  Created by Kevin McKee
//

import MetalKit
import SwiftUI
import VimKitShaders

private let renderEncoderLabel = "VimRenderEncoder"
private let renderEncoderDebugGroupName = "VimDrawGroup"

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

        // Encode the uniforms to send to the vertex function
        renderEncoder.setVertexBuffer(uniformBuffer, offset: uniformBufferOffset, index: .uniforms)

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
    }

    /// Draws the entire scene.
    /// - Parameter renderEncoder: the render encoder
    func drawScene(renderEncoder: MTLRenderCommandEncoder) {
        guard let geometry, let pipelineState else { return }

        renderEncoder.pushDebugGroup(renderEncoderDebugGroupName)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFrontFacing(.clockwise)
        renderEncoder.setCullMode(.none)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setTriangleFillMode(fillMode)

        // Filter any hidden instances
        let instances = geometry.instances.filter{ !$0.hidden }
        let start = Date.now // TODO: Follow up: for now just perform a simple timeout check

        for instance in instances {
            guard abs(start.timeIntervalSinceNow) < frameTimeLimit else { break }
            drawInstance(instance, renderEncoder: renderEncoder)
        }
        renderEncoder.popDebugGroup()
    }

    /// Performs any draws after the main scene draw.
    /// - Parameter renderEncoder: the render encoder
    func didDrawScene(renderEncoder: MTLRenderCommandEncoder) {
        skycube?.draw(renderEncoder: renderEncoder)
    }

    /// Determines if the instance should be drawn or not.
    /// - Parameter instance: the instance to test
    /// - Returns: true if the instance should be drawn.
    private func shouldDrawInstance(_ instance: Geometry.Instance) -> Bool {
        guard !instance.hidden else {
            // Make an exception to the rule if the instance is selected
            // as this instance can be room, level, or other naturally hidden element
            return instance.selected
        }
        guard let boundingBox = instance.boundingBox else { return false }
        return camera.contains(boundingBox)
    }

    /// Draws a single instance.
    /// - Parameters:
    ///   - instance: the geometry instance
    ///   - renderEncoder: the render encoder
    private func drawInstance(_ instance: Geometry.Instance, renderEncoder: MTLRenderCommandEncoder) {

        guard let geometry,
              let positionsBuffer = geometry.positionsBuffer,
              let normalsBuffer = geometry.normalsBuffer,
              let mesh = instance.mesh,
              let range = mesh.submeshes else { return }

        // Set the buffers to pass to the GPU
        renderEncoder.setVertexBuffer(positionsBuffer, offset: 0, index: .positions)
        renderEncoder.setVertexBuffer(normalsBuffer, offset: 0, index: .normals)
        renderEncoder.setFragmentTexture(baseColorTexture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)

        let submeshes = geometry.submeshes[range]
        for (i, submesh) in submeshes.enumerated() {
            guard let material = submesh.material, material.rgba.w > .zero else { continue }
            renderEncoder.pushDebugGroup("SubMesh[\(i)]")

            // Set the mesh uniforms
            var uniforms = instanceUniforms(instance, submesh: submesh)
            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<InstanceUniforms>.size, index: .instanceUniforms)
            // Draw the submesh using the indices
            drawSubmesh(geometry, submesh, renderEncoder)

            renderEncoder.popDebugGroup()
        }
    }

    /// Draws the submesh using indexed primitives.
    /// - Parameters:
    ///   - geometry: the geometry
    ///   - submesh: the submesh
    ///   - renderEncoder: the render encoder to use
    private func drawSubmesh(_ geometry: Geometry, _ submesh: Geometry.Submesh, _ renderEncoder: MTLRenderCommandEncoder) {

        guard let indexBuffer = geometry.indexBuffer else { return }
        renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: submesh.indices.count, indexType: .uint32, indexBuffer: indexBuffer, indexBufferOffset: submesh.indexBufferOffset)
    }
}

// MARK: Per Mesh Uniforms

extension VimRenderer {

    /// Returns the per instance uniforms for the specifed submesh in the specified instance
    /// - Parameters:
    ///   - instance: the geometry instance
    ///   - submesh: the submesh
    /// - Returns: the instance unifroms
    func instanceUniforms(_ instance: Geometry.Instance, submesh: Geometry.Submesh) -> InstanceUniforms {
        let color = instance.selected ? Color.objectSelectionColor.channels : submesh.material?.rgba ?? .zero
        return InstanceUniforms(
            identifier: Int32(instance.idenitifer),
            matrix: instance.matrix,
            color: color,
            glossiness: submesh.material?.glossiness ?? .half,
            smoothness: submesh.material?.smoothness ?? .half,
            xRay: instance.selected ? false : xRayMode
        )
    }
}
