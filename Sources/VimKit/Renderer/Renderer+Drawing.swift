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
private let labelOnScreenCommandBuffer = "OnScreenCommandBuffer"
private let labelOffScreenCommandBuffer = "OffScreenCommandBuffer"
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
        guard let onScreenCommandBuffer = commandQueue.makeCommandBuffer(),
              let offScreenCommandBuffer = commandQueue.makeCommandBuffer() else { return }
        onScreenCommandBuffer.label = labelOnScreenCommandBuffer
        offScreenCommandBuffer.label = labelOffScreenCommandBuffer

        // Update the per-frame state
        updatFrameState()

        // Perform the offscreen work
        var commandBuffer = offScreenCommandBuffer

        commandBuffer.addCompletedHandler { @Sendable (_ commandBuffer) in
            let gpuTime = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
            let kernelTime = commandBuffer.kernelEndTime - commandBuffer.kernelStartTime
            self.didRenderFrame(gpuTime: gpuTime, kernelTime: kernelTime)
        }

        // Build the draw descriptor
        var descriptor = makeDrawDescriptor(commandBuffer: commandBuffer)

        // Perform setup on all of the render passes.
        for renderPass in renderPasses {
            renderPass.willDraw(descriptor: descriptor)
        }

        // Commit the offscreen work and switch command buffers
        commandBuffer.commit()
        commandBuffer = onScreenCommandBuffer
        descriptor.commandBuffer = commandBuffer

        // Delay getting the renderPassDescriptor until absolutely needed. This avoids holding
        // onto the drawable and blocking the display pipeline any longer than necessary
        guard let drawable = context.destinationProvider.currentDrawable,
              let renderPassDescriptor = makeRenderPassDescriptor() else { return }
        descriptor.renderPassDescriptor = renderPassDescriptor

        // Make the render encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        // Make the draw call on the render passes
        for renderPass in renderPasses {
            renderPass.draw(descriptor: descriptor, renderEncoder: renderEncoder)
        }

        // End render encoding
        renderEncoder.endEncoding()

        // Perform post draw calls on the render passes
        for renderPass in renderPasses {
            renderPass.didDraw(descriptor: descriptor)
        }

        // Schedule the presentation and commit
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Builds a draw descriptor for use in the per-frame render passes.
    /// - Parameters:
    ///   - commandBuffer: the command buffer
    ///   - renderPassDescriptor: the render pass descriptor
    /// - Returns: a new draw descriptor
    func makeDrawDescriptor(commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor? = nil) -> DrawDescriptor {
        .init(
            commandBuffer: commandBuffer,
            renderPassDescriptor: renderPassDescriptor,
            framesBuffer: framesBuffer,
            framesBufferOffset: framesBufferOffset,
            visibilityResultBuffer: visibilityResultBuffer,
            visibilityResults: currentVisibleResults)
    }

    /// Gathers and publishes rendering stats.
    nonisolated func didRenderFrame(gpuTime: TimeInterval, kernelTime: TimeInterval) {
        Task { @MainActor in
            self.updateStats(gpuTime: gpuTime, kernelTime: kernelTime)
        }
    }
}
