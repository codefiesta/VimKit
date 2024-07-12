//
//  VimCompositorRenderer.swift
//  VimViewer
//
//  Created by Kevin McKee
//
#if os(visionOS)
import ARKit
import Combine
import CompositorServices
import MetalKit
import simd
import SwiftUI
import VimKit
import VimKitShaders

private let renderThreadName = "VimCompositorRendererThread"

/// A type that provides a Metal Renderer using CompositorServices for rendering VIM files on VisionOS.
///
/// For more information about CompositorServices see the following WWDC videos and tutorials.
/// -  https://developer.apple.com/videos/play/wwdc2023/10089/
/// -  https://developer.apple.com/videos/play/wwdc2023/10082
/// -  https://developer.apple.com/documentation/compositorservices/drawing_fully_immersive_content_using_metal
public class VimCompositorRenderer: VimRenderer {

    // The context that provides all of the data we need
    let context: VimCompositorContext
    // Used for timing
    let clock: LayerRenderer.Clock

    /// Initializes the layer renderer with the provided context.
    ///
    /// - Parameters:
    ///   - context: The compositor context
    public init(_ context: VimCompositorContext) {
        self.context = context
        self.clock = LayerRenderer.Clock()
        super.init(context)

        // Subscribe to hand tracking updates
        context.dataProviderContext.$handUpdates.sink { (_) in
        }.store(in: &subscribers)

        // Subscribe to world tracking transform updates
        context.dataProviderContext.$transform.sink { (_) in
        }.store(in: &subscribers)

        // Register for spatial events
        context.layerRenderer.onSpatialEvent = { eventCollection in
            let events = eventCollection.map { $0 }
            self.handle(events: events)
        }
    }

    /// Starts the ARKit Data Providers tracking tasks.
    /// See: https://developer.apple.com/documentation/visionos/setting-up-access-to-arkit-data
    private func startTracking() async {

        let worldTrackingTask = Task {
            await context.dataProviderContext.publishWorldTrackingUpdates()
        }
        let handTrackingTask = Task {
            await context.dataProviderContext.publishHandTrackingUpdates()
        }
        tasks.append(contentsOf: [worldTrackingTask, handTrackingTask])
    }

    private func stop() {
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
        for subsriber in subscribers {
            subsriber.cancel()
        }
        subscribers.removeAll()
    }

    /// Starts our main render loop
    public func start() {
        Task {
            await startTracking()
        }
        // Set up and run the Metal render loop.
        let renderThread = Thread {
            // Start the engine rendering loop
            self.loop()
        }
        renderThread.name = renderThreadName
        renderThread.start()

    }

    /// Provides our main render loop
    private func loop() {

        var isRunning = true
        while isRunning {
            switch context.layerRenderer.state {
            case .paused:
                // Wait until the scene appears
                context.layerRenderer.waitUntilRunning()
            case .running:
                // Render the next frame. 
                autoreleasepool {
                    renderNewFrame()
                }
            case .invalidated:
                // Exit the render loop.
                isRunning = false
            @unknown default:
                fatalError("Unknown renderer state \(context.layerRenderer.state)")
            }
        }

        // Stop the engine
        stop()
    }

    /// See: [Update and encode a single frame of content](https://developer.apple.com/documentation/compositorservices/drawing_fully_immersive_content_using_metal#4193619)
    func renderNewFrame() {

        // Fetch the next frame to use for drawing
        guard let frame = context.layerRenderer.queryNextFrame() else { return }

        // Mark the start of the update phase.
        frame.startUpdate()

        // TODO: Perform frame independent work

        // Mark the end of the update phase.
        frame.endUpdate()

        // Pause the rendering loop until optimal rendering time
        guard let timing = frame.predictTiming() else { return }
        clock.wait(until: timing.optimalInputTime)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let drawable = frame.queryDrawable() else { return }

        _ = inFlightSemaphore.wait(timeout: .distantFuture)

        // Mark the start of submission phase.
        frame.startSubmission()

        let timeInterval = LayerRenderer.Clock.Instant.epoch.duration(to: drawable.frameTiming.presentationTime).timeInterval
        drawable.deviceAnchor = context.queryDeviceAnchor(timeInterval)

        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { (_) in
            semaphore.signal()
        }

        // Build a render pass descriptor for the current drawable
        let renderPassDescriptor = buildRenderPassDescriptor(drawable)

        // Encode and commit the drawing commands
        draw(drawable, commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor)
        drawable.encodePresent(commandBuffer: commandBuffer)
        commandBuffer.commit()

        // Mark the end of your GPU submission.
        frame.endSubmission()
    }
}

// MARK: Per Frame Uniforms

extension VimCompositorRenderer {

    /// Updates the per frame uniforms from the camera
    ///
    /// - Parameters:
    ///   - drawable: the drawable to use
    func updateUniforms(_ drawable: LayerRenderer.Drawable) {

        // Build the uniforms for the specified view index
        func uniforms(_ index: Int) -> Uniforms {

            // Update our camera from the drawable view
            camera.update(drawable, index: index)
            return Uniforms(
                cameraPosition: context.vim.camera.position,
                viewMatrix: context.vim.camera.viewMatrix,
                projectionMatrix: context.vim.camera.projectionMatrix
            )
        }

        uniformBufferAddress[0].uniforms.0 = uniforms(0)
        if drawable.views.count > 1 {
            uniformBufferAddress[1].uniforms.1 = uniforms(1)
        }
    }
}

#endif
