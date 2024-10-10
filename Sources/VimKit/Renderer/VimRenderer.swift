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

@MainActor
open class VimRenderer: NSObject {

    /// The context that provides all of the data we need
    let context: VimRendererContext

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

    open var commandQueue: MTLCommandQueue!
    open var pipelineState: MTLRenderPipelineState?
    open var depthStencilState: MTLDepthStencilState?
    open var samplerState: MTLSamplerState?
    open var baseColorTexture: MTLTexture?
    open var instancePickingTexture: MTLTexture?
    open var renderPassDescriptor: MTLRenderPassDescriptor?
    open var computePipelineState: MTLComputePipelineState?
    open var indirectCommandBuffer: MTLIndirectCommandBuffer?

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

    /// The viewport size.
    open var viewportSize: SIMD2<Float> = .zero {
        didSet {
            if oldValue != viewportSize {
                camera.viewportSize = viewportSize
                buildTextures()
            }
        }
    }

    var shapes: Shapes?
    var skycube: Skycube?
    var visibility: Visibility?

    /// The max time to render a frame.
    /// TODO: Calculate from frame rate.
    open var frameTimeLimit: TimeInterval = 0.3

    /// Common initializer.
    /// - Parameter context: the rendering context
    public init(_ context: VimRendererContext) {
        self.context = context
        super.init()

        shapes = .init(context)
        skycube = .init(context)
        visibility = .init(context, bufferCount: maxBuffersInFlight + 1)

        // Load the metal resources
        loadMetal()

        // Uniforms
        uniformBuffer = device.makeBuffer(length: alignedUniformsSize * maxBuffersInFlight, options: [.storageModeShared])
    }
}

// MARK: Per Frame Uniforms

extension VimRenderer {

    /// Update the per-frame rendering state
    public func updatFrameState() {
        updateDynamicBufferState()
        updateUniforms()
        visibility?.updateFrameState()
    }

    /// Update the state of our revolving uniform buffers before rendering
    private func updateDynamicBufferState() {
        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex
        uniformBufferAddress = uniformBuffer.contents().advanced(by: uniformBufferOffset).assumingMemoryBound(to: UniformsArray.self)
    }

    /// Updates the per-frame uniforms from the camera
    private func updateUniforms() {

        let uniforms = Uniforms(
            cameraPosition: camera.position,
            viewMatrix: camera.viewMatrix,
            projectionMatrix: camera.projectionMatrix,
            sceneTransform: camera.sceneTransform
        )
        uniformBufferAddress[0].uniforms.0 = uniforms
    }
}

// MARK: Object Selection

extension VimRenderer {

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
