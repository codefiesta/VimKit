//
//  Renderer+Shapes.swift
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

extension Renderer {

    /// A struct that draws shapes.
    @MainActor
    struct Shapes {

        /// The context that provides all of the data we need
        let context: RendererContext

        /// Returns the camera.
        var camera: Vim.Camera {
            context.vim.camera
        }

        let allocator: MTKMeshBufferAllocator
        let boxMesh: MTKMesh
        let cylinderMesh: MTKMesh
        let planeMesh: MTKMesh
        let sphereMesh: MTKMesh
        let pipelineState: MTLRenderPipelineState?
        let depthStencilState: MTLDepthStencilState?

        /// Common initializer.
        /// - Parameter context: the rendering context
        init?(_ context: RendererContext) {
            self.context = context
            guard let library = MTLContext.makeLibrary(),
                  let device = context.destinationProvider.device else { return nil }

            let extents: SIMD3<Float> = .one

            self.allocator = MTKMeshBufferAllocator(device: device)
            let box = MDLMesh(boxWithExtent: extents, segments: .one, inwardNormals: false, geometryType: .triangles, allocator: allocator)
            let cylinder = MDLMesh(cylinderWithExtent: extents, segments: [50, 50], inwardNormals: false, topCap: false, bottomCap: false, geometryType: .triangles, allocator: allocator)
            let plane = MDLMesh(planeWithExtent: extents, segments: .one, geometryType: .triangles, allocator: allocator)
            let sphere = MDLMesh(sphereWithExtent: extents, segments: [50, 50], inwardNormals: false, geometryType: .triangles, allocator: allocator)

            guard let boxMesh = try? MTKMesh(mesh: box, device: device),
                  let cylinderMesh = try? MTKMesh(mesh: cylinder, device: device),
                  let planeMesh = try? MTKMesh(mesh: plane, device: device),
                  let sphereMesh = try? MTKMesh(mesh: sphere, device: device) else { return nil }
            self.boxMesh = boxMesh
            self.cylinderMesh = cylinderMesh
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

        /// Draws the shape with the specified render encoder, mesh, color and transform.
        /// - Parameters:
        ///   - renderEncoder: the render encoder
        ///   - mesh: the mesh
        ///   - color: the shape color
        ///   - transform: the shape transform matrix
        private func drawShape(renderEncoder: MTLRenderCommandEncoder,
                               mesh: MTKMesh,
                               color: SIMD4<Float> = shapeDefaultColor,
                               transform: float4x4 = .identity) {

            guard let pipelineState else { return }
            renderEncoder.pushDebugGroup(shapeGroupName)
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setDepthStencilState(depthStencilState)

            var color = color
            var transform = transform

            // Set the buffers to pass to the GPU
            renderEncoder.setVertexBytes(&color, length: MemoryLayout<SIMD4<Float>>.size, index: .colors)
            renderEncoder.setVertexBytes(&transform, length: MemoryLayout<float4x4>.size, index: .instances)
            renderEncoder.setVertexBuffer(mesh.vertexBuffers.first?.buffer, offset: 0, index: .positions)

            // Draw the mesh
            for submesh in mesh.submeshes {
                renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: 0)
            }

            // Pop the debug group
            renderEncoder.popDebugGroup()
        }

        /// Draws a box from the specified axis aligned bounding box.
        /// - Parameters:
        ///   - renderEncoder: the render encoder
        ///   - box: the axis aligned bounding box (assumes the box is already in world coordinates)
        ///   - color: the color of the box
        func drawBox(renderEncoder: MTLRenderCommandEncoder,
                     box: MDLAxisAlignedBoundingBox?,
                     color: SIMD4<Float> = shapeDefaultColor) {

            guard let box else { return }

            // Position + Scale
            var transform: float4x4 = .identity
            transform.position = box.center
            transform.scale(box.extents)
            // Draw the box using the box mesh
            drawShape(renderEncoder: renderEncoder, mesh: boxMesh, color: color, transform: transform)
        }

        /// Draws a cylinder.
        /// - Parameters:
        ///   - renderEncoder: the render encoder
        ///   - transform: the cylinder transform matrix
        ///   - color: the color of the cylinder
        func drawCylinder(renderEncoder: MTLRenderCommandEncoder,
                       transform: float4x4 = .identity,
                       color: SIMD4<Float> = shapeDefaultColor) {
            // Draw the cylinder using the cylinder mesh
            drawShape(renderEncoder: renderEncoder, mesh: cylinderMesh, color: color, transform: transform)
        }

        /// Draws a plane.
        /// - Parameters:
        ///   - renderEncoder: the render encoder
        ///   - plane: the plane to draw
        ///   - transform: the plane transform matrix
        ///   - color: the color of the plane
        ///   - scaleToBounds: if true, will scale the plane to the extent of the model bounds
        func drawPlane(renderEncoder: MTLRenderCommandEncoder,
                       plane: SIMD4<Float>?,
                       transform: float4x4 = .identity,
                       color: SIMD4<Float> = shapeDefaultColor,
                       scaleToBounds: Bool = true) {
            guard let plane else { return }

            var transform = transform

            // Scale the bounds of the plane to the model bounds
            if scaleToBounds, let bounds = context.vim.geometry?.bounds {
                transform.scale(bounds.extents)
            }

            // Set the plane position
            transform.position = plane.xyz * plane.w
            // Multiply the transform by the scene transform (most likely z-up)
            transform *= camera.sceneTransform
            // Rotate the plane around it's normal axis by 180° (expressed in radians)
            transform.rotate(around: plane.xyz, by: Float.pi / 2)
            // Draw the plane using the plane mesh
            drawShape(renderEncoder: renderEncoder, mesh: planeMesh, color: color, transform: transform)
        }

        /// Draws a sphere.
        /// - Parameters:
        ///   - renderEncoder: the render encoder
        ///   - transform: the sphere transform matrix
        ///   - color: the color of the sphere
        func drawSphere(renderEncoder: MTLRenderCommandEncoder,
                       transform: float4x4 = .identity,
                       color: SIMD4<Float> = shapeDefaultColor) {
            // Draw the sphere using the sphere mesh
            drawShape(renderEncoder: renderEncoder, mesh: sphereMesh, color: color, transform: transform)
        }
    }
}
