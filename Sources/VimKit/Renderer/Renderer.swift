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

private let maxBuffersInFlight = 3

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

    open var visibilityResultBuffer: MTLBuffer? {
        guard let visibility = renderPasses.last as? RenderPassVisibility else {
            return nil
        }
        return visibility.currentVisibilityResultBuffer
    }

    open var renderPasses = [RenderPass]()

    open var commandQueue: MTLCommandQueue!
    open var pipelineState: MTLRenderPipelineState?
    open var depthStencilState: MTLDepthStencilState?
    open var samplerState: MTLSamplerState?
    open var baseColorTexture: MTLTexture?
    open var instancePickingTexture: MTLTexture?
    open var renderPassDescriptor: MTLRenderPassDescriptor?

    /// The compute pipeline state.
    open var computePipelineState: MTLComputePipelineState?
    /// The indirect command buffer to use to issue visibility results.
    open var icb: MTLIndirectCommandBuffer?
    /// Argument buffer containing the indirect command buffer encoded in the kernel
    open var icbBuffer: MTLBuffer?

    // Uniforms Buffer
    public let alignedUniformsSize = ((MemoryLayout<UniformsArray>.size + 255) / 256) * 256
    open var uniformsBuffer: MTLBuffer!
    open var uniformsBufferIndex: Int = 0
    open var uniformsBufferOffset: Int = 0
    open var uniformsBufferAddress: UnsafeMutablePointer<UniformsArray>!

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

        // Make the uniforms buffer
        uniformsBuffer = device.makeBuffer(length: alignedUniformsSize * maxBuffersInFlight, options: [.storageModeShared])
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
        uniformsBufferIndex = (uniformsBufferIndex + 1) % maxBuffersInFlight
        uniformsBufferOffset = alignedUniformsSize * uniformsBufferIndex
        uniformsBufferAddress = uniformsBuffer.contents().advanced(by: uniformsBufferOffset).assumingMemoryBound(to: UniformsArray.self)
    }

    /// Updates the per-frame uniforms from the camera
    private func updateUniforms() {

        let uniforms = Uniforms(
            cameraPosition: camera.position,
            viewMatrix: camera.viewMatrix,
            projectionMatrix: camera.projectionMatrix,
            sceneTransform: camera.sceneTransform
        )
        uniformsBufferAddress[0].uniforms.0 = uniforms
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
