//
//  Renderer.swift
//
//
//  Created by Kevin McKee
//

import Combine
import Metal
import MetalKit
import Spatial
import VimKitShaders

private let alignedFramesSize = ((MemoryLayout<Frame>.size + 255) / 256) * 256
private let maxFramesInFlight = 3
private let maxStatEntries = 100

@MainActor
open class Renderer: NSObject {

    /// The context that provides all of the data we need
    let context: RendererContext

    /// Allow override for subclasses
    open var geometry: Geometry? {
        context.vim.geometry
    }

    /// Returns the camera.
    open var camera: Vim.Camera {
        context.vim.camera
    }

    /// Returns the rendering options.
    open var options: Vim.Options {
        context.vim.options
    }

    /// Configuration option for wireframing the model.
    open var fillMode: MTLTriangleFillMode {
        options.wireFrame == true ? .lines : .fill
    }

    /// Configuration option for rendering in xray mode.
    open var xRayMode: Bool {
        options.xRay
    }

    /// The Metal device.
    open var device: MTLDevice {
        context.destinationProvider.device!
    }

    /// Boolean flag indicating if indirect command buffers are supported or not.
    open var supportsIndirectCommandBuffers: Bool {
        device.supportsFamily(.apple4)
    }

    /// Returns the visibility results buffer.
    var visibilityResultBuffer: MTLBuffer? {
        guard let visibility = renderPasses.last as? RenderPassVisibility else {
            return nil
        }
        return visibility.currentVisibilityResultBuffer
    }

    /// Returns the subset of instanced mesh indexes that have returned true from the occlusion query.
    var currentVisibleResults: [Int] {
        guard let visibility = renderPasses.last as? RenderPassVisibility else {
            return .init()
        }
        return visibility.currentVisibleResults
    }

    /// The array of render passes used to draw.
    open var renderPasses = [RenderPass]()

    /// The renderer command queue
    open var commandQueue: MTLCommandQueue!
    open var instancePickingTexture: MTLTexture?

    // Frames Buffer
    open var framesBuffer: MTLBuffer!
    open var framesBufferIndex: Int = 0
    open var framesBufferOffset: Int = 0
    open var framesBufferAddress: UnsafeMutablePointer<Frame>!

    /// Combine Subscribers which drive rendering events
    open var subscribers = Set<AnyCancellable>()

    /// Cancellable tasks.
    open var tasks = [Task<(), Never>]()

    /// The viewport size.
    open var viewportSize: SIMD2<Float> = .zero {
        didSet {
            if oldValue != viewportSize {
                resize()
            }
        }
    }

    /// Provides the clock used for latency stats.
    private var clock: Clock = .init()
    /// The current index of the rotating stat entries.
    private var statsIndex: Int = 0
    /// The rendering stat entries.
    private var stats = [Stat](repeating: .init(), count: maxStatEntries)

    /// Common initializer.
    /// - Parameter context: the rendering context
    public init(_ context: RendererContext) {
        self.context = context
        super.init()
        self.commandQueue = device.makeCommandQueue()

        // Make the render passes
        let renderPasses: [RenderPass?] = [
            supportsIndirectCommandBuffers ? RenderPassIndirect(context) : RenderPassDirect(context),
            RenderPassSkycube(context),
            RenderPassVisibility(context)
        ]
        self.renderPasses = renderPasses.compactMap{ $0 }

        // Make the frames buffer
        framesBuffer = device.makeBuffer(length: alignedFramesSize * maxFramesInFlight,
                                         options: [.storageModeShared])
    }
}

// MARK: Per Frame Uniforms

extension Renderer {

    /// Update the per-frame rendering state
    public func updatFrameState() {
        updateDynamicBufferState()
        updateUniforms()

        // Update the frame state for the render passes
        for (i, _) in renderPasses.enumerated() {
            renderPasses[i].updateFrameState()
        }
    }

    /// Update the state of our revolving uniform buffers before rendering
    private func updateDynamicBufferState() {
        framesBufferIndex = (framesBufferIndex + 1) % maxFramesInFlight
        framesBufferOffset = alignedFramesSize * framesBufferIndex
        framesBufferAddress = framesBuffer.contents()
            .advanced(by: framesBufferOffset)
            .assumingMemoryBound(to: Frame.self)
    }

    /// Updates the per-frame uniforms from the camera
    private func updateUniforms() {

        // Frame Camera Data
        framesBufferAddress[0].cameras.0.position = camera.position
        framesBufferAddress[0].cameras.0.viewMatrix = camera.viewMatrix
        framesBufferAddress[0].cameras.0.projectionMatrix = camera.projectionMatrix
        framesBufferAddress[0].cameras.0.sceneTransform = camera.sceneTransform

        framesBufferAddress[0].screenSize = viewportSize
        framesBufferAddress[0].screenSizeInverse = .one / viewportSize
        framesBufferAddress[0].physicalSize = viewportSize
        framesBufferAddress[0].physicalSizeInverse = .one / viewportSize
        framesBufferAddress[0].xRay = xRayMode

//        frameData->physicalSize = float2{(float)_physicalWidth, (float)_physicalHeight};
//        frameData->invPhysicalSize = 1.0f / frameData->physicalSize;

    }
}

// MARK: Object Selection

extension Renderer {

    /// Informs the renderer that the model was tapped at the specified point.
    /// Creates a region at the specified point the size of a single pixel and
    /// grabs the byte encoded at that pixel on the instance index texture.
    /// - Parameter point: the screen point
    public func didTap(at point: SIMD2<Float>) {
        guard let geometry, let texture = instancePickingTexture else { return }
        let region = MTLRegionMake2D(Int(point.x), Int(point.y), 1, 1)
        let bytesPerRow = MemoryLayout<Int32>.stride * texture.width
        var pixel: Int32 = .empty
        texture.getBytes(&pixel, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        guard pixel != .empty else {
            context.vim.erase()
            return
        }

        let id = Int(pixel)
        guard let index = geometry.instanceOffsets.firstIndex(of: id) else { return }

        let query = camera.unprojectPoint(point)
        var point3D: SIMD3<Float> = .zero

        // Raycast into the instance
        if let result = geometry.instances[index].raycast(geometry, query: query) {
            point3D = result.position
            debugPrint("✅", point3D)
        }

        // Select the instance so the event gets published.
        context.vim.select(id: id, point: point3D)
    }
}

// MARK: Stats

extension Renderer {

    /// Provides a clock to time frame rendering times and calculate stats.
    private struct Clock {

        /// The time the clock was started.
        private var start: TimeInterval = .now

        /// Resets the clock
        mutating func reset() {
            start = .now
        }

        /// Returns the elapsed time between now and the start time.
        func elapsedTime() -> TimeInterval {
            .now - start
        }
    }

    /// Provides a container struct that allows us to average frame render times.
    private struct Stat: Sendable {
        /// The number of frames.
        var count: Int = .zero
        /// The total accumulation of latency time.
        var latency: Double = .zero
        /// The max latency time.
        var maxLatency: Double = .zero
    }

    /// Gathers and publishes rendering stats.
    /// - Parameters:
    ///   - gpuTime: The time in seconds it took the GPU to finish executing the command buffer
    ///   - kernelTime: The time in seconds it took the CPU to finish scheduling the command buffer.
    func updateStats(gpuTime: TimeInterval, kernelTime: TimeInterval) {
        let elapsed = clock.elapsedTime()

        stats[statsIndex].latency += elapsed
        stats[statsIndex].count += 1
        stats[statsIndex].maxLatency = max(stats[statsIndex].maxLatency, elapsed)

        if elapsed > 1.0 {

            // Publish the statsout
            if stats[statsIndex].count > .zero {
                context.vim.stats.averageLatency = stats[statsIndex].latency / Double(stats[statsIndex].count)
            } else {
                context.vim.stats.averageLatency = .zero
            }
            context.vim.stats.maxLatency = stats[statsIndex].maxLatency

            // Reset the stats at this index and move to the next buffer
            clock.reset()
            stats[statsIndex].count = .zero
            stats[statsIndex].latency = .zero
            stats[statsIndex].maxLatency = .zero
            statsIndex = (statsIndex + 1) % 100
        }
    }
}
