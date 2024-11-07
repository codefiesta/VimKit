//
//  RenderPass.swift
//  VimKit
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

private let labelInstancePickingTexture = "InstancePickingTexture"

/// A type that holds render pass draw arguments.
struct DrawArguments {
    /// The command buffer to use.
    let commandBuffer: MTLCommandBuffer
    /// The render pass descriptor to use.
    let renderPassDescriptor: MTLRenderPassDescriptor?
    /// The uniforms buffer to use.
    let uniformsBuffer: MTLBuffer?
    /// The uniforms buffer offset
    let uniformsBufferOffset: Int
    /// Provides a subset of instanced mesh indexes that have returned true from the occlusion query.
    let visibilityResults: [Int]
}

@MainActor
protocol RenderPass {

    /// The rendering context.
    var context: RendererContext { get }
    /// Returns the current metal device.
    var device: MTLDevice { get }
    /// Returns the textures.
    var textures: [MTLTexture?] { get set }

    /// Performs a draw call with the specified command buffer and render pass descriptor.
    /// - Parameters:
    ///   - arguments: the draw arguments to use
    func draw(arguments: DrawArguments)

    /// Performs resize operations (resizing textures).
    /// - Parameter viewportSize: the new viewport size.
    mutating func resize(viewportSize: SIMD2<Float>)
}

extension RenderPass {

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
    /// - Returns: a new render pipeline state or nil
    func makeRenderPipelineState(_ context: RendererContext,
                            _ vertexDescriptor: MTLVertexDescriptor,
                            _ label: String?,
                            _ vertexFunctionName: String?,
                            _ fragmentFunctionName: String?) -> MTLRenderPipelineState? {

        guard let library = makeLibrary() else { return nil }

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
        pipelineDescriptor.supportIndirectCommandBuffers = true

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else { return nil }
        return pipelineState

    }

    /// Makes the default depth stencil state.
    /// - Returns: the default depth stencil state
    func makeDepthStencilState() -> MTLDepthStencilState? {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
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

    /// Builds the textures when the viewport size changes.
    /// - Parameter viewportSize: the new viewport size
    mutating func makeTextures(viewportSize: SIMD2<Float>) {

        guard viewportSize != .zero else { return }

        let width = Int(viewportSize.x)
        let height = Int(viewportSize.y)

        // Instance Picking Texture
        let instancePickingTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Sint, width: width, height: height, mipmapped: false)
        instancePickingTextureDescriptor.usage = .renderTarget

        textures[1] = device.makeTexture(descriptor: instancePickingTextureDescriptor)
        textures[1]?.label = labelInstancePickingTexture
    }

    /// Default resize function
    /// - Parameter viewportSize: the new viewport size
    mutating func resize(viewportSize: SIMD2<Float>) {
        makeTextures(viewportSize: viewportSize)
    }
}
