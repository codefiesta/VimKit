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

        init?(_ context: VimRendererContext) {

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

            let textureDimensions: SIMD2<Int32> = [160, 160]
            let textureLoader = MTKTextureLoader(device: device)
            let mdkSkycubeTexture = MDLSkyCubeTexture(name: nil,
                                        channelEncoding: .uInt8,
                                        textureDimensions: textureDimensions,
                                        turbidity: 0,
                                        sunElevation: 0,
                                        upperAtmosphereScattering: 0,
                                        groundAlbedo: 0)
            guard let skycubeTexture = try? textureLoader.newTexture(texture: mdkSkycubeTexture, options: [.SRGB: false]) else { return nil }
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
