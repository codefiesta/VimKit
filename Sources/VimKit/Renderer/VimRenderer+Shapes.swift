//
//  VimRenderer+Shapes.swift
//
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

private let debugCullingSphereGroupName = "DebugCullingSphere"
private let sphereVertexFunctionName = "vertexSphere"
private let sphereFragmentFunctionName = "fragmentSphere"

extension VimRenderer {

    /// A struct that draws shapes.
    struct Shapes {

        /// The context that provides all of the data we need
        let context: VimRendererContext

        /// Returns the camera.
        var camera: Vim.Camera {
            return context.vim.camera
        }

        /// Configuration option for rendering the culling sphere (for debugging purposes).
        var cullingSphere: Bool {
            return context.vim.options[.cullingSphere] ?? false
        }

        let sphereMesh: MTKMesh
        let pipelineState: MTLRenderPipelineState?
        let depthStencilState: MTLDepthStencilState?

        /// Common initializer.
        /// - Parameter context: the rendering context
        init?(_ context: VimRendererContext) {
            self.context = context
            guard let library = MTLContext.makeLibrary(),
                  let device = context.destinationProvider.device else {
                return nil
            }

            let extents: SIMD3<Float> = [1.0, 1.0, 1.0]
            let segment: UInt32 = 100

            let allocator = MTKMeshBufferAllocator(device: device)
            let sphere = MDLMesh(sphereWithExtent: extents, segments: [segment, segment], inwardNormals: false, geometryType: .triangles, allocator: allocator)

            guard let mesh = try? MTKMesh(mesh: sphere, device: device) else { return nil }
            sphereMesh = mesh

            let vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(sphere.vertexDescriptor)
            let pipelineDescriptor = MTLRenderPipelineDescriptor()

            // Color Attachment
            pipelineDescriptor.colorAttachments[0].pixelFormat = context.destinationProvider.colorFormat
            pipelineDescriptor.colorAttachments[1].pixelFormat = .r32Sint
            pipelineDescriptor.depthAttachmentPixelFormat = context.destinationProvider.depthFormat
            pipelineDescriptor.stencilAttachmentPixelFormat = context.destinationProvider.depthFormat

            pipelineDescriptor.vertexFunction = library.makeFunction(name: sphereVertexFunctionName)
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: sphereFragmentFunctionName)
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

        /// Draws the shapes.
        /// - Parameter renderEncoder: the render encoder
        func draw(renderEncoder: MTLRenderCommandEncoder) {
            drawCullingSphere(renderEncoder: renderEncoder)
        }

        /// Draws the frustum culling sphere (for debugging purposes).
        /// - Parameter renderEncoder: the render encoder
        private func drawCullingSphere(renderEncoder: MTLRenderCommandEncoder) {
            guard cullingSphere else { return }

            guard let pipelineState else { return }
            renderEncoder.pushDebugGroup(debugCullingSphereGroupName)
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setDepthStencilState(depthStencilState)
            renderEncoder.setTriangleFillMode(.lines)

            var matrix: float4x4 = .identity
            matrix.position = camera.sphere.center

            // Set the buffers to pass to the GPU
            renderEncoder.setVertexBuffer(sphereMesh.vertexBuffers[0].buffer, offset: 0, index: .positions)

            renderEncoder.setVertexBytes(&matrix, length: MemoryLayout<float4x4>.size, index: .instances)

            for submesh in sphereMesh.submeshes {
                renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: 0)
            }
            renderEncoder.popDebugGroup()

        }
    }
}
