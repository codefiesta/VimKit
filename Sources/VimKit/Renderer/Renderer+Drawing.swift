//
//  Renderer+Drawing.swift
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

extension Renderer: MTKViewDelegate {

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

public extension Renderer {

    /// Renders a new frame.
    private func renderNewFrame() {

        guard let geometry, geometry.state == .ready else { return }
        guard let drawable = context.destinationProvider.currentDrawable,
              let renderPassDescriptor = makeRenderPassDescriptor(visibilityResultBuffer),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Update the per-frame state
        updatFrameState()

        // Build the draw descriptor
        let descriptor = makeDrawDescriptor(commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor)

        // Perform setup on all of the render passes.
        for renderPass in renderPasses {
            renderPass.willDraw(descriptor: descriptor)
        }

        // Make the render encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        // Make the draw call on the render passes
        for renderPass in renderPasses {
            renderPass.draw(descriptor: descriptor, renderEncoder: renderEncoder)
        }

        // End encoding
        renderEncoder.endEncoding()

        // Schedule the presentation and commit
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Builds a draw descriptor for use in the per-frame render passes.
    /// - Parameters:
    ///   - commandBuffer: the command buffer
    ///   - renderPassDescriptor: the render pass descriptor
    /// - Returns: a new draw descriptor
    func makeDrawDescriptor(commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor) -> DrawDescriptor {
        .init(
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            uniformsBuffer: uniformsBuffer,
            uniformsBufferOffset: uniformsBufferOffset,
            visibilityResultBuffer: visibilityResultBuffer,
            visibilityResults: currentVisibleResults)
    }
}
