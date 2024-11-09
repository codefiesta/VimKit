//
//  Renderer+Metal.swift
//  
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

private let labelInstancePickingTexture = "InstancePickingTexture"

extension Renderer {

    /// Builds a render pass descriptor from the destination provider's (MTKView) current render pass descriptor.
    /// - Parameters:
    ///   - visibilityResultBuffer: the visibility result write buffer
    func makeRenderPassDescriptor(_ visibilityResultBuffer: MTLBuffer? = nil) -> MTLRenderPassDescriptor? {

        // Use the render pass descriptor from the MTKView
        let renderPassDescriptor = context.destinationProvider.currentRenderPassDescriptor

        // Instance Picking Texture Attachment
        renderPassDescriptor?.colorAttachments[1].texture = instancePickingTexture
        renderPassDescriptor?.colorAttachments[1].loadAction = .clear
        renderPassDescriptor?.colorAttachments[1].storeAction = .store

        // Depth attachment
        renderPassDescriptor?.depthAttachment.clearDepth = 1.0

        // Visibility Results
        renderPassDescriptor?.visibilityResultBuffer = visibilityResultBuffer
        return renderPassDescriptor
    }

    /// Handles view resize.
    func resize() {
        // Update the camera
        camera.viewportSize = viewportSize

        // Rebuild the textures.
        buildTextures()

        // Inform the render passes that the view has been resized
        for (i, _) in renderPasses.enumerated() {
            renderPasses[i].resize(viewportSize: viewportSize)
        }
    }

    /// Builds the textures when the viewport size changes.
    func buildTextures() {

        guard viewportSize != .zero else { return }

        let width = Int(viewportSize.x)
        let height = Int(viewportSize.y)

        // Instance Picking Texture
        let instancePickingTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Sint, width: width, height: height, mipmapped: false)
        instancePickingTextureDescriptor.usage = .renderTarget

        instancePickingTexture = device.makeTexture(descriptor: instancePickingTextureDescriptor)
        instancePickingTexture?.label = labelInstancePickingTexture
    }
}
