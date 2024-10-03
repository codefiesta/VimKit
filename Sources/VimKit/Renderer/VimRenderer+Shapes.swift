//
//  VimRenderer+Shapes.swift
//
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

private let shapeGroupName = "Shape"
private let shapeVertexFunctionName = "vertexShape"
private let shapeFragmentFunctionName = "fragmentShape"
// Default Shape color (Purple with 0.5 opacity)
private let shapeDefaultColor: SIMD4<Float> = [1.0, .zero, 1.0, .half]

extension VimRenderer {

    /// A struct that draws shapes.
    @MainActor
    struct Shapes {

        /// The context that provides all of the data we need
        let context: VimRendererContext

        /// Returns the camera.
        var camera: Vim.Camera {
            context.vim.camera
        }

        let allocator: MTKMeshBufferAllocator
        let boxMesh: MTKMesh
        let planeMesh: MTKMesh
        let sphereMesh: MTKMesh
        let pipelineState: MTLRenderPipelineState?
        let depthStencilState: MTLDepthStencilState?

        /// Common initializer.
        /// - Parameter context: the rendering context
        init?(_ context: VimRendererContext) {
            self.context = context
            guard let library = MTLContext.makeLibrary(),
                  let device = context.destinationProvider.device else { return nil }

            let extents: SIMD3<Float> = .one

            self.allocator = MTKMeshBufferAllocator(device: device)
            let box = MDLMesh(boxWithExtent: extents, segments: [1, 1, 1], inwardNormals: false, geometryType: .triangles, allocator: allocator)
            let plane = MDLMesh(planeWithExtent: extents, segments: [1, 1], geometryType: .triangles, allocator: allocator)
            let sphere = MDLMesh(sphereWithExtent: extents, segments: [50, 50], inwardNormals: false, geometryType: .triangles, allocator: allocator)

            guard let boxMesh = try? MTKMesh(mesh: box, device: device),
                  let planeMesh = try? MTKMesh(mesh: plane, device: device),
                  let sphereMesh = try? MTKMesh(mesh: sphere, device: device) else { return nil }
            self.boxMesh = boxMesh
            self.planeMesh = planeMesh
            self.sphereMesh = sphereMesh

            // Build the main pipeline
            let vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(sphereMesh.vertexDescriptor)
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

            pipelineDescriptor.colorAttachments[1].pixelFormat = .r32Sint
            pipelineDescriptor.depthAttachmentPixelFormat = context.destinationProvider.depthFormat
            pipelineDescriptor.stencilAttachmentPixelFormat = context.destinationProvider.depthFormat

            pipelineDescriptor.vertexFunction = library.makeFunction(name: shapeVertexFunctionName)
            pipelineDescriptor.fragmentFunction = library.makeFunction(name: shapeFragmentFunctionName)
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

        /// Draws the shapes with the specified render encoder, mesh, and draw closure.
        /// - Parameters:
        ///   - renderEncoder: the render encoder
        ///   - mesh: the mesh
        ///   - draw: the main draw closure
        func drawShapes(renderEncoder: MTLRenderCommandEncoder, mesh: MTKMesh, draw: (MTKMesh) -> Void) {
            guard let pipelineState else { return }
            renderEncoder.pushDebugGroup(shapeGroupName)
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setDepthStencilState(depthStencilState)
            renderEncoder.setTriangleFillMode(.lines)

            // Set the buffers to pass to the GPU
            renderEncoder.setVertexBuffer(mesh.vertexBuffers.first?.buffer, offset: 0, index: .positions)
            // Execute the draw closure
            draw(mesh)
            // Pop the debug group
            renderEncoder.popDebugGroup()
        }

        /// Draws a box from the specified axis aligned bounding box.
        /// - Parameters:
        ///   - renderEncoder: the render encoder
        ///   - box: the axis aligned bounding box (assumes the box is already in world coordinates)
        ///   - color: the color of the shape
        func drawBoundingBox(renderEncoder: MTLRenderCommandEncoder,
                             box: MDLAxisAlignedBoundingBox?,
                             _ color: SIMD4<Float> = shapeDefaultColor) {

            guard let box else { return }

            // Position + Scale
            var transform: float4x4 = .identity
            transform.position = box.center
            transform.scale(box.extents)

            // Color
            var color = color

            drawShapes(renderEncoder: renderEncoder, mesh: boxMesh) { mesh in

                renderEncoder.setVertexBytes(&color, length: MemoryLayout<SIMD4<Float>>.size, index: .colors)
                renderEncoder.setVertexBytes(&transform, length: MemoryLayout<float4x4>.size, index: .instances)
                renderEncoder.setTriangleFillMode(.fill)

                for submesh in mesh.submeshes {
                    renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: 0)
                }
            }

        }
    }
}
