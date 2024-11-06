//
//  VimRenderer+Metal.swift
//  
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

private let functionNameVertexMain = "vertexMain"
private let functionNameFragmentMain = "fragmentMain"
private let functionNameEncodeIndirectCommands = "encodeIndirectCommands"
private let labelInstancePickingTexture = "InstancePickingTexture"
private let labelPipeline = "VimRendererPipeline"
private let labelICB = "VimIndirectCommandBuffer"

extension VimRenderer {

    /// Loads all our metal resources.
    public func loadMetal() {

        // Load all the shader files with a metal file extension in the project
        let library = MTLContext.makeLibrary()!
        let vertexFunction = library.makeFunction(name: functionNameVertexMain)
        let fragmentFunction = library.makeFunction(name: functionNameFragmentMain)
        let vertexDescriptor = MTLContext.buildVertexDescriptor()

        commandQueue = device.makeCommandQueue()
        pipelineState = buildPipelineState(library, vertexFunction, fragmentFunction, vertexDescriptor, labelPipeline)
        depthStencilState = buildDepthStencilState()
        samplerState = buildSamplerState()
        buildComputePipelineState(library)
    }

    /// Builds the render pipeline state.
    /// - Parameters:
    ///   - library: the metal library
    ///   - vertexFunction: the vertex function
    ///   - fragmentFunction: the fragment function
    ///   - vertexDescriptor: the vertex descriptor
    ///   - pipelineLabel: the pipeline label
    /// - Returns: the pipeline state
    private func buildPipelineState(_ library: MTLLibrary, _ vertexFunction: MTLFunction?, _ fragmentFunction: MTLFunction?, _ vertexDescriptor: MTLVertexDescriptor, _ pipelineLabel: String) -> MTLRenderPipelineState? {

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = pipelineLabel

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

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else { return nil }
        return pipeline
    }

    /// Builds the compute pipeline state.
    /// - Parameter library: the metal library
    private func buildComputePipelineState(_ library: MTLLibrary) {

        guard supportsIndirectCommandBuffers else {
            debugPrint("💩 Indirect command buffers are not supported on this device.")
            return
        }

        let descriptor = MTLIndirectCommandBufferDescriptor()
        descriptor.commandTypes = [.drawIndexed]
        descriptor.inheritBuffers = false
        descriptor.inheritPipelineState = true

        guard let function = library.makeFunction(name: functionNameEncodeIndirectCommands),
              let cps = try? device.makeComputePipelineState(function: function) else {
            return
        }

        // Create icb using private storage mode since only the GPU will read+write to/from buffer
        let maxCommandCount = 1024 * 64
        let icb = device.makeIndirectCommandBuffer(descriptor: descriptor,
                                                   maxCommandCount: maxCommandCount,
                                                   options: [.storageModePrivate])
        icb?.label = labelICB
        self.indirectCommandBuffer = icb
        self.computePipelineState = cps

        let argumentEncoder = function.makeArgumentEncoder(.commandBufferContainer)
        indirectArgumentBuffer = device.makeBuffer(length: argumentEncoder.encodedLength,
                                                   options: [.storageModeShared])
        argumentEncoder.setArgumentBuffer(indirectArgumentBuffer, offset: 0)
        argumentEncoder.setIndirectCommandBuffer(indirectCommandBuffer, index: .commandBuffer)

    }

    /// Builds the depth stencil state
    private func buildDepthStencilState() -> MTLDepthStencilState? {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }

    /// Builds the sampler state
    private func buildSamplerState() -> MTLSamplerState? {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.normalizedCoordinates = true
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        return device.makeSamplerState(descriptor: samplerDescriptor)
    }

    /// Builds a render pass descriptor from the destination provider's (MTKView) current render pass descriptor.
    func buildRenderPassDescriptor() {

        // Use the render pass descriptor from the MTKView
        let renderPassDescriptor = context.destinationProvider.currentRenderPassDescriptor

        // Instance Picking Texture Attachment
        renderPassDescriptor?.colorAttachments[1].texture = instancePickingTexture
        renderPassDescriptor?.colorAttachments[1].loadAction = .clear
        renderPassDescriptor?.colorAttachments[1].storeAction = .store
        // Depth attachment
        renderPassDescriptor?.depthAttachment.clearDepth = 1.0
        // Visibility Results
        renderPassDescriptor?.visibilityResultBuffer = visibility?.currentVisibilityResultBuffer

        self.renderPassDescriptor = renderPassDescriptor
    }

    /// Builds the textures when the viewport size changes.
    func buildTextures() {

        guard viewportSize != .zero else { return }

        let width = Int(viewportSize.x)
        let height = Int(viewportSize.y)

        // Instance Picking Texture
        let instancePickingTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Sint, width: width, height: height, mipmapped: false)
        instancePickingTextureDescriptor.usage = .renderTarget

        instancePickingTexture = device.makeTexture(descriptor: instancePickingTextureDescriptor)
        instancePickingTexture?.label = labelInstancePickingTexture
    }
}
