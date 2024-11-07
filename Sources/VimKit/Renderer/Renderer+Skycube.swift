//
//  Rendererer+Skycube.swift
//
//
//  Created by Kevin McKee
//

import Combine
import MetalKit
import VimKitShaders

private let skycubeGroupName = "Skycube"
private let skycubeVertexFunctionName = "vertexSkycube"
private let skycubeFragmentFunctionName = "fragmentSkycube"

extension Renderer {

    /// A struct that draws the scene background skycube.
    @MainActor
    class Skycube {

        /// The context that provides all of the data we need
        let context: RendererContext

        /// Returns the rendering options.
        var options: Vim.Options {
            context.vim.options
        }

        let mesh: MTKMesh
        let textureLoader: MTKTextureLoader
        var texture: MTLTexture?
        let sky: MDLSkyCubeTexture
        let pipelineState: MTLRenderPipelineState?
        let depthStencilState: MTLDepthStencilState?

        /// Combine Subscribers which drive rendering events
        var subscribers = Set<AnyCancellable>()

        /// Initializes the skycube with the provided context.
        /// - Parameter context: the rendering context.
        init?(_ context: RendererContext) {
            guard let library = MTLContext.makeLibrary(),
                  let device = context.destinationProvider.device else {
                return nil
            }
            self.context = context
            self.textureLoader = MTKTextureLoader(device: device)

            let allocator = MTKMeshBufferAllocator(device: device)
            let cube = MDLMesh(boxWithExtent: .one,
                               segments: .one,
                               inwardNormals: true,
                               geometryType: .triangles,
                               allocator: allocator)
            guard let cubeMesh = try? MTKMesh(mesh: cube, device: device) else { return nil }
            self.mesh = cubeMesh

            let options = context.vim.options
            let textureDimensions: SIMD2<Int32> = [256, 256]
            self.sky = MDLSkyCubeTexture(name: skycubeGroupName,
                                                      channelEncoding: .uInt8,
                                                      textureDimensions: textureDimensions,
                                                      turbidity: options.turbidity,
                                                      sunElevation: options.sunElevation,
                                                      upperAtmosphereScattering: options.upperAtmosphereScattering,
                                                      groundAlbedo: options.groundAlbedo)

            guard let newTexture = try? textureLoader.newTexture(texture: sky) else { return nil }
            self.texture = newTexture

            let vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(cube.vertexDescriptor)

            let pipelineDescriptor = MTLRenderPipelineDescriptor()

            // Color Attachment
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

            pipelineDescriptor.vertexFunction = library.makeFunction(name: skycubeVertexFunctionName)
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: skycubeFragmentFunctionName)
            pipelineDescriptor.vertexDescriptor = vertexDescriptor

            let depthStencilDescriptor = MTLDepthStencilDescriptor()
            depthStencilDescriptor.depthCompareFunction = .lessEqual
            depthStencilDescriptor.isDepthWriteEnabled = true

            guard let depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor),
                  let pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else {
                return nil
            }
            self.depthStencilState = depthStencilState
            self.pipelineState = pipelineState

            // Observe the options.
            context.vim.$options.sink { _ in
                self.updateSkycube()
            }.store(in: &subscribers)
        }

        /// Updates the sky cube texture from the scene settings.
        private func updateSkycube() {
            sky.turbidity = options.turbidity
            sky.sunElevation = options.sunElevation
            sky.upperAtmosphereScattering = options.upperAtmosphereScattering
            sky.groundAlbedo = options.groundAlbedo
            sky.update()
            guard let newTexture = try? textureLoader.newTexture(texture: sky) else { return }
            texture = newTexture
        }

        /// Draws the skycube.
        /// - Parameters:
        ///   - renderEncoder: the render encoder to use.
        ///   - uniformBuffer: the uniform buffer
        ///   - uniformBufferOffset: the uniform buffer offset
        ///   - samplerState: the sampler state
        func draw(renderEncoder: MTLRenderCommandEncoder,
                  uniformBuffer: MTLBuffer,
                  uniformBufferOffset: Int,
                  samplerState: MTLSamplerState?) {

            guard let pipelineState else { return }
            renderEncoder.pushDebugGroup(skycubeGroupName)
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setDepthStencilState(depthStencilState)

            // Set the buffers to pass to the GPU
            renderEncoder.setVertexBuffer(uniformBuffer, offset: uniformBufferOffset, index: .uniforms)
            for (_, vertexBuffer) in mesh.vertexBuffers.enumerated() {
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: .positions)
            }
            renderEncoder.setFragmentTexture(texture, index: 0)
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)

            let submesh = mesh.submeshes[0]
            renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: 0)
            renderEncoder.popDebugGroup()
        }
    }
}
