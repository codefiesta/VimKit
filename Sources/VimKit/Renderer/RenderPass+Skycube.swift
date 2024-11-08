//
//  RenderPass+Skycube.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Combine
import MetalKit
import VimKitShaders

private let skycubeGroupName = "Skycube"
private let skycubeVertexFunctionName = "vertexSkycube"
private let skycubeFragmentFunctionName = "fragmentSkycube"

/// Provides a render pass that draws the scene background skycube.
class RenderPassSkycube: RenderPass {

    /// The context that provides all of the data we need
    let context: RendererContext

    var pipelineState: MTLRenderPipelineState?
    var depthStencilState: MTLDepthStencilState?
    var samplerState: MTLSamplerState?
    var mesh: MTKMesh?
    var textureLoader: MTKTextureLoader?
    var texture: MTLTexture?
    var sky: MDLSkyCubeTexture?

    /// Combine Subscribers which drive rendering events
    var subscribers = Set<AnyCancellable>()

    /// Initializes the render pass with the provided rendering context.
    /// - Parameter context: the rendering context.
    init?(_ context: RendererContext) {
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
        let sky = MDLSkyCubeTexture(name: skycubeGroupName,
                                                  channelEncoding: .uInt8,
                                                  textureDimensions: textureDimensions,
                                                  turbidity: options.turbidity,
                                                  sunElevation: options.sunElevation,
                                                  upperAtmosphereScattering: options.upperAtmosphereScattering,
                                                  groundAlbedo: options.groundAlbedo)
        self.sky = sky
        guard let newTexture = try? textureLoader?.newTexture(texture: sky) else { return nil }
        self.texture = newTexture

        guard let vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(cube.vertexDescriptor) else { return nil }

        self.pipelineState = makeRenderPipelineState(context, vertexDescriptor, skycubeGroupName, skycubeVertexFunctionName, skycubeFragmentFunctionName, false)
        self.depthStencilState = makeDepthStencilState(.lessEqual)
        self.samplerState = makeSamplerState()

        // Observe the options.
        context.vim.$options.sink { _ in
            self.updateSkycube()
        }.store(in: &subscribers)
    }

    /// Performs a draw call with the specified command buffer and render pass descriptor.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    func draw(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {

        // Encode the buffers
        encode(descriptor: descriptor, renderEncoder: renderEncoder)

        // Make the draw call
        drawSkycube(renderEncoder: renderEncoder)
    }

    private func drawSkycube(renderEncoder: MTLRenderCommandEncoder) {
        guard let mesh else { return }
        renderEncoder.pushDebugGroup(skycubeGroupName)
        let submesh = mesh.submeshes[0]
        renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: 0)
        renderEncoder.popDebugGroup()

    }

    /// Encodes the buffer data into the render encoder.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func encode(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {
        guard let mesh, let pipelineState else { return }
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setVertexBuffer(descriptor.uniformsBuffer, offset: descriptor.uniformsBufferOffset, index: .uniforms)

        for (_, vertexBuffer) in mesh.vertexBuffers.enumerated() {
            renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: .positions)
        }
        renderEncoder.setFragmentTexture(texture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
    }

    /// Updates the sky cube texture from the scene settings.
    private func updateSkycube() {
        guard let sky, let textureLoader else { return }
        sky.turbidity = options.turbidity
        sky.sunElevation = options.sunElevation
        sky.upperAtmosphereScattering = options.upperAtmosphereScattering
        sky.groundAlbedo = options.groundAlbedo
        sky.update()
        guard let newTexture = try? textureLoader.newTexture(texture: sky) else { return }
        texture = newTexture
    }
}
