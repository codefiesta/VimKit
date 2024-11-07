//
//  CompositorRenderer.swift
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


/// A type that provides a Metal Renderer using CompositorServices for rendering VIM files on VisionOS.
///
/// For more information about CompositorServices see the following WWDC videos and tutorials.
/// -  https://developer.apple.com/videos/play/wwdc2023/10089/
/// -  https://developer.apple.com/videos/play/wwdc2023/10082
/// -  https://developer.apple.com/documentation/compositorservices/drawing_fully_immersive_content_using_metal
public class CompositorRenderer: Renderer {

    // The context that provides all of the data we need
    let context: CompositorContext
    // Used for timing
    let clock: LayerRenderer.Clock

    /// Initializes the layer renderer with the provided context.
    ///
    /// - Parameters:
    ///   - context: The compositor context
    public init(_ context: CompositorContext) {
        self.context = context
        self.clock = LayerRenderer.Clock()
        super.init(context)

        // Wait for geometry to load into a ready state
        context.vim.geometry?.$state.sink { state in
            Task { @MainActor in
                guard state == .ready else { return }
                self.start()
            }
        }.store(in: &subscribers)

        // Subscribe to hand tracking updates
        context.dataProvider.$handUpdates.sink { (_) in
        }.store(in: &subscribers)

        // Subscribe to world tracking transform updates
        context.dataProvider.$transform.sink { (_) in
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
            await context.dataProvider.publishWorldTrackingUpdates()
        }
        let handTrackingTask = Task {
            await context.dataProvider.publishHandTrackingUpdates()
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

    /// Starts the main render loop.
    @MainActor
    public func start() {
        Task {
            await startTracking()
        }

        // Start the run loop
        loop()
    }

    /// Runs main render loop.
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

        // Mark the start of submission phase.
        frame.startSubmission()

        let timeInterval = LayerRenderer.Clock.Instant.epoch.duration(to: drawable.frameTiming.presentationTime).timeInterval
        drawable.deviceAnchor = context.queryDeviceAnchor(timeInterval)

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

extension CompositorRenderer {

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
                cameraPosition: camera.position,
                viewMatrix: camera.viewMatrix,
                projectionMatrix: camera.projectionMatrix,
                sceneTransform: camera.sceneTransform
            )
        }

        uniformBufferAddress[0].uniforms.0 = uniforms(0)
        if drawable.views.count > 1 {
            uniformBufferAddress[1].uniforms.1 = uniforms(1)
        }
    }
}

#endif
