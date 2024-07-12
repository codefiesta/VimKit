//
//  VimRenderer.swift
//
//
//  Created by Kevin McKee
//

import Combine
import Metal
import MetalKit
import Spatial
import VimKitShaders

private let maxBuffersInFlight = 3

open class VimRenderer: NSObject {

    /// The context that provides all of the data we need
    let context: VimRendererContext

    /// Allow override for subclasses
    open var geometry: Geometry? {
        return context.vim.geometry
    }

    /// Returns the camera.
    open var camera: Vim.Camera {
        return context.vim.camera
    }

    /// The Metal device.
    open var device: MTLDevice {
        return context.destinationProvider.device!
    }

    open var commandQueue: MTLCommandQueue!
    open var pipelineState: MTLRenderPipelineState?
    open var depthStencilState: MTLDepthStencilState?
    open var samplerState: MTLSamplerState?
    open var baseColorTexture: MTLTexture?
    open var instanceIndexTexture: MTLTexture?
    open var renderPassDescriptor: MTLRenderPassDescriptor?

    // Semaphore
    public let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)

    // Uniforms Buffer
    public let alignedUniformsSize = ((MemoryLayout<UniformsArray>.size + 255) / 256) * 256
    open var uniformBuffer: MTLBuffer!
    open var uniformBufferIndex: Int = 0
    open var uniformBufferOffset: Int = 0
    open var uniformBufferAddress: UnsafeMutablePointer<UniformsArray>!

    /// Combine Subscribers which drive rendering events
    open var subscribers = Set<AnyCancellable>()

    /// Cancellable tasks.
    open var tasks = [Task<(), Never>]()

    /// Configuration option for wireframing the model.
    open var fillMode: MTLTriangleFillMode {
        return context.vim.options[.wireFrame] == true ? .lines : .fill
    }

    /// Configuration option for rendering in xray mode.
    open var xRayMode: Bool {
        return context.vim.options[.xRay] ?? false
    }

    /// The viewport size.
    open var viewportSize: SIMD2<Float> = .zero {
        didSet {
            if oldValue != viewportSize {
                camera.viewportSize = viewportSize
                buildTextures()
            }
        }
    }

    var skycube: Skycube?

    /// The max time to render a frame.
    /// TODO: Calculate from frame rate.
    open var frameTimeLimit: TimeInterval = 0.3

    /// Common initializer.
    /// - Parameter context: the rendering context
    public init(_ context: VimRendererContext) {
        self.context = context
        super.init()

        skycube = Skycube(context)

        // Load the metal resources
        loadMetal()
        // Uniforms
        uniformBuffer = device.makeBuffer(length: alignedUniformsSize * maxBuffersInFlight, options: [.storageModeShared])
    }
}

// MARK: Per Frame Uniforms

extension VimRenderer {

    // Updates the per-frame uniforms from the camera
    func updateUniforms() {

        let uniforms = Uniforms(
            cameraPosition: camera.position,
            viewMatrix: camera.viewMatrix,
            projectionMatrix: camera.projectionMatrix
        )
        uniformBufferAddress[0].uniforms.0 = uniforms
    }

    /// Update the state of our revolving uniform buffers before rendering
    public func updateDynamicBufferState() {
        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex
        uniformBufferAddress = uniformBuffer.contents().advanced(by: uniformBufferOffset).assumingMemoryBound(to: UniformsArray.self)
    }
}

// MARK: Object Selection

extension VimRenderer {

    /// Informs the renderer that the model was tapped at the specified point.
    /// Creates a region at the specified point the size of a single pixel and
    /// grabs the byte encoded at that pixel on the instance index texture.
    /// - Parameter point: the screen point
    public func didTap(at point: SIMD2<Float>) {
        guard let texture = instanceIndexTexture else { return }
        let region = MTLRegionMake2D(Int(point.x), Int(point.y), 1, 1)
        let bytesPerRow = MemoryLayout<Int32>.stride * texture.width
        var pixel: Int32 = .empty
        texture.getBytes(&pixel, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        guard pixel != .empty else {
            context.vim.erase()
            return
        }
        let id = Int(pixel)

        /// Raycast into the instance
        var point3D: SIMD3<Float> = .zero
        let query = camera.unprojectPoint(point)
        if let geometry,
           let instance = geometry.instance(for: id),
           let result = instance.raycast(geometry, query: query) {
            point3D = result.position
        }
        // Select the instance so the event gets published.
        context.vim.select(id: id, point: point3D)
    }
}
