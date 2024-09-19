//
//  VimRendererer+Skycube.swift
//
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

private let skycubeDebugGroupName = "Skycube"
private let skycubeVertexFunctionName = "vertexSkycube"
private let skycubeFragmentFunctionName = "fragmentSkycube"

extension VimRenderer {

    /// A struct that draws the scene background skycube.
    struct Skycube {

        let mesh: MTKMesh
        let texture: MTLTexture?
        let pipelineState: MTLRenderPipelineState?
        let depthStencilState: MTLDepthStencilState?

        /// Haze in the sky. 0 is a clear - 1 spreads the sun’s color
        var turbidity: Float = .half
        /// How high the sun is in the sky. 0.5 is on the horizon. 1.0 is overhead.
        var sunElevation: Float = 0.75
        /// Atmospheric scattering influences the color of the sky from reddish through orange tones to the sky at midday.
        var upperAtmosphereScattering: Float = .half
        /// How clear the sky is. 0 is clear, while 10 can produce intense colors. It’s best to keep turbidity and upper atmosphere scattering low if you have high albedo.
        var groundAlbedo: Float = 0.1

        init?(_ context: VimRendererContext) {

            // Determine how high the sun is based on the hour of day
            let hour = Calendar.current.component(.hour, from: .now)
            sunElevation = Float(hour) / Float(24)
            
            guard let library = MTLContext.makeLibrary(),
                  let device = context.destinationProvider.device else {
                return nil
            }

            let allocator = MTKMeshBufferAllocator(device: device)
            let cube = MDLMesh(boxWithExtent: .one,
                               segments: .one,
                               inwardNormals: true,
                               geometryType: .triangles,
                               allocator: allocator)
            guard let cubeMesh = try? MTKMesh(mesh: cube, device: device) else { return nil }
            mesh = cubeMesh

            let textureDimensions: SIMD2<Int32> = [256, 256]
            let textureLoader = MTKTextureLoader(device: device)
            let mdkSkycubeTexture = MDLSkyCubeTexture(name: nil,
                                                      channelEncoding: .uInt8,
                                                      textureDimensions: textureDimensions,
                                                      turbidity: turbidity,
                                                      sunElevation: sunElevation,
                                                      upperAtmosphereScattering: upperAtmosphereScattering,
                                                      groundAlbedo: groundAlbedo)

            guard let skycubeTexture = try? textureLoader.newTexture(texture: mdkSkycubeTexture) else { return nil }
            texture = skycubeTexture

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
        }

        func draw(renderEncoder: MTLRenderCommandEncoder) {

            guard let pipelineState else { return }
            renderEncoder.pushDebugGroup(skycubeDebugGroupName)
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setDepthStencilState(depthStencilState)

            // Set the buffers to pass to the GPU
            renderEncoder.setVertexBuffer(mesh.vertexBuffers[0].buffer, offset: 0, index: .positions)
            renderEncoder.setFragmentTexture(texture, index: 0)

            let submesh = mesh.submeshes[0]
            renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: 0)
            renderEncoder.popDebugGroup()
        }
    }
}
