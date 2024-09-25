//
//  VimCompositorRenderer+Metal.swift
//  
//
//  Created by Kevin McKee
//

#if os(visionOS)
import CompositorServices
import MetalKit
import VimKit
import VimKitShaders

extension VimCompositorRenderer {

    /// Builds a single render descriptor
    /// See: https://developer.apple.com/documentation/compositorservices/drawing_fully_immersive_content_using_metal#4225666
    /// - Parameter drawable: the drawable
    /// - Returns: a new render pass descriptor
    func buildRenderPassDescriptor(_ drawable: LayerRenderer.Drawable) -> MTLRenderPassDescriptor {

        // Set the viewport size change which will trigger a texture build if the size has changed
        let width = drawable.colorTextures.first?.width ?? 0
        let height = drawable.colorTextures.first?.height ?? 0
        viewportSize = [Float(width), Float(height)]

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.rasterizationRateMap = drawable.rasterizationRateMaps.first

        // Color Attachment
        renderPassDescriptor.colorAttachments[0].texture = drawable.colorTextures.first
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = context.destinationProvider.clearColor

        // Instance Picking Texture Attachment
        renderPassDescriptor.colorAttachments[1].texture = instancePickingTexture
        renderPassDescriptor.colorAttachments[1].loadAction = .clear
        renderPassDescriptor.colorAttachments[1].storeAction = .store

        // Depth Attachment
        renderPassDescriptor.depthAttachment.texture = drawable.depthTextures.first
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .store
        renderPassDescriptor.depthAttachment.clearDepth = 1.0

        // Stencil Attachment
        renderPassDescriptor.stencilAttachment.texture = drawable.depthTextures.first

        if context.layerRenderer.configuration.layout == .layered {
            renderPassDescriptor.renderTargetArrayLength = drawable.views.count
        }

        return renderPassDescriptor
    }
}

#endif
