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

extension VimRenderer {

    /// A struct that draws shapes.
    struct Shapes {

        /// The context that provides all of the data we need
        let context: VimRendererContext

        /// Returns the camera.
        var camera: Vim.Camera {
            return context.vim.camera
        }

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
                  let device = context.destinationProvider.device else {
                return nil
            }

            let extents: SIMD3<Float> = .one
            let segment: UInt32 = 12

            let allocator = MTKMeshBufferAllocator(device: device)
            let box = MDLMesh(boxWithExtent: extents, segments: [segment, segment, segment], inwardNormals: false, geometryType: .triangles, allocator: allocator)
            let plane = MDLMesh(planeWithExtent: extents, segments: [segment, segment], geometryType: .triangles, allocator: allocator)
            let sphere = MDLMesh(sphereWithExtent: extents, segments: [segment, segment], inwardNormals: false, geometryType: .triangles, allocator: allocator)

            guard let boxMesh = try? MTKMesh(mesh: box, device: device),
                  let planeMesh = try? MTKMesh(mesh: plane, device: device),
                  let sphereMesh = try? MTKMesh(mesh: sphere, device: device)
                   else { return nil }
            self.boxMesh = boxMesh
            self.planeMesh = planeMesh
            self.sphereMesh = sphereMesh

            let vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(sphereMesh.vertexDescriptor)
            let pipelineDescriptor = MTLRenderPipelineDescriptor()

            // Color Attachment
            pipelineDescriptor.colorAttachments[0].pixelFormat = context.destinationProvider.colorFormat
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

        /// Draws the shapes.
        /// - Parameter renderEncoder: the render encoder
        func draw(renderEncoder: MTLRenderCommandEncoder) {
            // Noop
        }

        /// Draws the shapes with the specified render encoder, mesh, and draw closure.
        /// - Parameters:
        ///   - renderEncoder: the render encoder
        ///   - mesh: the mesh
        ///   - draw: the main draw closure
        private func drawShapes(renderEncoder: MTLRenderCommandEncoder, mesh: MTKMesh, draw: (MTKMesh) -> Void) {
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
    }
}
