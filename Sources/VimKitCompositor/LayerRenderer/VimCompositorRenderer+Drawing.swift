//
//  File.swift
//  
//
//  Created by Kevin McKee
//

#if os(visionOS)
import CompositorServices
import MetalKit
import VimKit

private let renderEncoderLabel = "VimCompositorRenderEncoder"

extension VimCompositorRenderer {

    /// The draw call.
    /// - Parameters:
    ///   - drawable: the drawable
    ///   - commandBuffer: the command buffer
    ///   - renderPassDescriptor: the render pass descriptor
    func draw(_ drawable: LayerRenderer.Drawable,
              commandBuffer: MTLCommandBuffer,
              renderPassDescriptor: MTLRenderPassDescriptor) {

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

        // Update the per-frame state
        updatFrameState()

        // Update the per-frame uniforms
        updateUniforms(drawable)

        // Perform any pre scene draws
        willDrawScene(renderEncoder: renderEncoder)

        // Draw the scene
        drawScene(renderEncoder: renderEncoder)

        // Perform any post scene draws
        didDrawScene(renderEncoder: renderEncoder)

        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
    }
}

#endif
