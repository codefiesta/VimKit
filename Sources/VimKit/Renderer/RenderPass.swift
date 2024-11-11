//
//  RenderPass.swift
//  VimKit
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

/// A type that holds render pass draw arguments.
public struct DrawDescriptor {
    /// The command buffer to use.
    var commandBuffer: MTLCommandBuffer
    /// The render pass descriptor to use.
    var renderPassDescriptor: MTLRenderPassDescriptor?
    /// The uniforms buffer to use.
    let uniformsBuffer: MTLBuffer?
    /// The uniforms buffer offset
    let uniformsBufferOffset: Int
    /// The current  visibility write buffer which samples passing the depth and stencil tests are counted.
    let visibilityResultBuffer: MTLBuffer?
    /// Provides a subset of instanced mesh indexes that have returned true from the occlusion query.
    let visibilityResults: [Int]
}

@MainActor
public protocol RenderPass {

    /// The rendering context.
    var context: RendererContext { get }
    /// Returns the camera.
    var camera: Vim.Camera { get }
    /// Returns the current metal device.
    var device: MTLDevice { get }
    /// Returns the geometry to render.
    var geometry: Geometry? { get }
    /// Returns the rendering options.
    var options: Vim.Options { get }
    /// Configuration option for wireframing the model.
    var fillMode: MTLTriangleFillMode { get }
    /// Configuration option for rendering in xray mode.
    var xRayMode: Bool { get }
    /// Returns true if the device supports indirect command buffers.
    var supportsIndirectCommandBuffers: Bool { get }

    /// Performs all encoding and setup options before drawing. Most render passes won't need to do anything here,
    /// but some render passes (such as indirect) need to setup compute encoders before drawing.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    func willDraw(descriptor: DrawDescriptor)

    /// Performs a draw call with the specified command buffer and render pass descriptor.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    func draw(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder)

    /// Performs resize operations (resizing textures).
    /// - Parameter viewportSize: the new viewport size.
    mutating func resize(viewportSize: SIMD2<Float>)

    /// Update the render pass per-frame rendering state (if needed).
    mutating func updateFrameState()
}

extension RenderPass {

    /// Returns the camera.
    var camera: Vim.Camera {
        context.vim.camera
    }

    /// The metal device.
    var device: MTLDevice {
        context.destinationProvider.device!
    }

    /// Returns the geometry to render.
    var geometry: Geometry? {
        context.vim.geometry
    }

    /// Returns the rendering options.
    var options: Vim.Options {
        context.vim.options
    }

    /// Configuration option for wireframing the model.
    var fillMode: MTLTriangleFillMode {
        options.wireFrame == true ? .lines : .fill
    }

    /// Configuration option for rendering in xray mode.
    var xRayMode: Bool {
        options.xRay
    }

    /// Boolean flag indicating if indirect command buffers are supported or not.
    var supportsIndirectCommandBuffers: Bool {
        device.supportsFamily(.apple4)
    }

    /// Makes the metal library.
    /// - Returns: a metal library
    func makeLibrary() -> MTLLibrary? {
        MTLContext.makeLibrary()
    }

    /// Makes a metal function with the specifed library and function name.
    /// - Parameters:
    ///   - library: the library to use
    ///   - name: the function name
    /// - Returns: the metal function or nil
    func makeFunction(_ library: MTLLibrary, _ name: String?) -> MTLFunction? {
        guard let name else { return nil }
        return library.makeFunction(name: name)
    }

    /// Makes the default render pipeline state
    /// - Parameters:
    ///   - context: the rendering context to use
    ///   - vertexDescriptor: the vertex descriptor to use
    ///   - label: the pipeline state label
    ///   - vertexFunctionName: the vertex function name
    ///   - fragmentFunctionName: the fragment function name
    ///   - supportIndirectCommandBuffers: flag indicating if icbs are supported
    /// - Returns: a new render pipeline state or nil
    func makeRenderPipelineState(_ context: RendererContext,
                                 _ vertexDescriptor: MTLVertexDescriptor,
                                 _ label: String?,
                                 _ vertexFunctionName: String?,
                                 _ fragmentFunctionName: String?,
                                 _ supportIndirectCommandBuffers: Bool = true) -> MTLRenderPipelineState? {

        guard let library = makeLibrary() else {
            debugPrint("💩")
            return nil
        }

        let vertexFunction = makeFunction(library, vertexFunctionName)
        let fragmentFunction = makeFunction(library, fragmentFunctionName)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = label

        // Alpha Blending
        pipelineDescriptor.colorAttachments[0].pixelFormat = context.destinationProvider.colorFormat
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        // Instance Picking
        pipelineDescriptor.colorAttachments[1].pixelFormat = .r32Sint

        pipelineDescriptor.depthAttachmentPixelFormat = context.destinationProvider.depthFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = context.destinationProvider.depthFormat

        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.maxVertexAmplificationCount = context.destinationProvider.viewCount
        pipelineDescriptor.vertexBuffers[.positions].mutability = .mutable
        pipelineDescriptor.supportIndirectCommandBuffers = supportIndirectCommandBuffers

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
            debugPrint("💩")
            return nil
        }
        return pipelineState

    }

    /// Makes the default depth stencil state.
    /// - Returns: the default depth stencil state
    /// - Parameters:
    ///   - depthCompare: the depth compare function
    ///   - isDepthWriteEnabled: flag enabling/disabling depth writing
    func makeDepthStencilState(_ depthCompare: MTLCompareFunction = .less, isDepthWriteEnabled: Bool = true) -> MTLDepthStencilState? {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = depthCompare
        depthStencilDescriptor.isDepthWriteEnabled = isDepthWriteEnabled
        return device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }

    /// Makes the default sampler state.
    /// - Returns: the default sampler state
    func makeSamplerState() -> MTLSamplerState? {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.normalizedCoordinates = true
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        return device.makeSamplerState(descriptor: samplerDescriptor)
    }

    /// Makes the default metal vertex descriptor
    /// - Returns: the default metal vertex descriptor
    func makeVertexDescriptor() -> MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()

        // Positions
        vertexDescriptor.attributes[.position].format = .float3
        vertexDescriptor.attributes[.position].bufferIndex = VertexAttribute.position.rawValue
        vertexDescriptor.attributes[.position].offset = 0

        // Normals
        vertexDescriptor.attributes[.normal].format = .float3
        vertexDescriptor.attributes[.normal].bufferIndex = VertexAttribute.normal.rawValue
        vertexDescriptor.attributes[.normal].offset = 0

        // Descriptor Layouts
        vertexDescriptor.layouts[.positions].stride = MemoryLayout<Float>.size * 3
        vertexDescriptor.layouts[.normals].stride = MemoryLayout<Float>.size * 3

        return vertexDescriptor
    }

    /// Default resize function
    /// - Parameter viewportSize: the new viewport size
    mutating func resize(viewportSize: SIMD2<Float>) { }

    /// Noop update frame state call
    mutating func updateFrameState() { }

    /// Noop `willDraw` operation. Most render passes won't need to do anything here,
    /// but some render passes (such as indirect) need to setup compute encoders before drawing.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    func willDraw(descriptor: DrawDescriptor) { }

}
