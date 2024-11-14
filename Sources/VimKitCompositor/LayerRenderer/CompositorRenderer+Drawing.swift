//
//  CompositorRenderer+Drawing.swift
//  
//
//  Created by Kevin McKee
//

#if os(visionOS)
import CompositorServices
import MetalKit
import VimKit

private let renderEncoderLabel = "VimCompositorRenderEncoder"

extension CompositorRenderer {

    /// The draw call.
    /// - Parameters:
    ///   - drawable: the drawable
    ///   - commandBuffer: the command buffer
    ///   - renderPassDescriptor: the render pass descriptor
    func draw(_ drawable: LayerRenderer.Drawable,
              commandBuffer: MTLCommandBuffer,
              renderPassDescriptor: MTLRenderPassDescriptor) {

        // Update the per-frame state
        updatFrameState()

        // Update the per-frame uniforms
        updateUniforms(drawable)

        // Build the draw descriptor
        let descriptor = makeDrawDescriptor(commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor)

        // Perform setup on all of the render passes.
        for renderPass in renderPasses {
            renderPass.willDraw(descriptor: descriptor)
        }

        // Make the render encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        renderEncoder.label = renderEncoderLabel

        let viewports = drawable.views.map { $0.textureMap.viewport }
        renderEncoder.setViewports(viewports)

        if drawable.views.count > 1 {
            var viewMappings = (0..<drawable.views.count).map {
                MTLVertexAmplificationViewMapping(viewportArrayIndexOffset: UInt32($0), renderTargetArrayIndexOffset: UInt32($0))
            }
            renderEncoder.setVertexAmplificationCount(viewports.count, viewMappings: &viewMappings)
        }

        // Make the draw call on the render passes
        for renderPass in renderPasses {
            renderPass.draw(descriptor: descriptor, renderEncoder: renderEncoder)
        }

        // End encoding
        renderEncoder.endEncoding()
    }
}

#endif
