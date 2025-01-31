//
//  RenderPass+Shapes.swift
//  VimKit
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

private let labelPipeline = "Shape"
private let functionNameVertex = "vertexShape"
private let functionNameFragment = "fragmentShape"
// Default Shape color (Purple with 0.5 opacity)
private let shapeDefaultColor: SIMD4<Float> = [1.0, .zero, 1.0, .half]

/// Provides a direct render pass.
class RenderPassShapes: RenderPass {

    /// The context that provides all of the data we need
    let context: RendererContext

    var allocator: MTKMeshBufferAllocator?
    var boxMesh: MTKMesh?
    var cylinderMesh: MTKMesh?
    var planeMesh: MTKMesh?
    var sphereMesh: MTKMesh?
    var pipelineState: MTLRenderPipelineState?
    var depthStencilState: MTLDepthStencilState?
    var samplerState: MTLSamplerState?

    /// Initializes the render pass with the provided rendering context.
    /// - Parameter context: the rendering context.
    init(_ context: RendererContext) {
        self.context = context
        let vertexDescriptor = makeVertexDescriptor()
        self.pipelineState = makeRenderPipelineState(context, vertexDescriptor, labelPipeline, functionNameVertex, functionNameFragment)
        self.depthStencilState = makeDepthStencilState()
        self.samplerState = makeSamplerState()
        makeMeshes()
    }

    /// Performs a draw call with the specified command buffer and render pass descriptor.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    func draw(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {

        // Encode the buffers
        encode(descriptor: descriptor, renderEncoder: renderEncoder)

        // Draw the clip planes
        drawClipPlanes(descriptor: descriptor, renderEncoder: renderEncoder)
    }

    /// Encodes the buffer data into the render encoder.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func encode(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {

        guard let pipelineState, let normalsBuffer = geometry?.normalsBuffer else { return }
        renderEncoder.pushDebugGroup(labelPipeline)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)

        // Setup the per frame buffers to pass to the GPU
        renderEncoder.setVertexBuffer(descriptor.framesBuffer, offset: descriptor.framesBufferOffset, index: .frames)
        renderEncoder.setVertexBuffer(normalsBuffer, offset: 0, index: .normals) // Not used but we are sharing the same vertex descriptor
    }

    /// Draws all valid clip planes.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func drawClipPlanes(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {
        let clipPlanes = camera.clipPlanes.filter{ $0 != .invalid }
        guard clipPlanes.isNotEmpty else { return }

        for plane in clipPlanes {
            drawPlane(renderEncoder: renderEncoder, plane: plane)
        }
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

        var color = color
        var transform = transform

        // Set the buffers to pass to the GPU
        renderEncoder.setVertexBytes(&color, length: MemoryLayout<SIMD4<Float>>.size, index: .colors)
        renderEncoder.setVertexBytes(&transform, length: MemoryLayout<float4x4>.size, index: .instances)

        for vertexBuffer in mesh.vertexBuffers {
            renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: .positions)
        }

        // Draw the mesh
        for submesh in mesh.submeshes {
            renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                indexCount: submesh.indexCount,
                                                indexType: submesh.indexType,
                                                indexBuffer: submesh.indexBuffer.buffer,
                                                indexBufferOffset: submesh.indexBuffer.offset)
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

        guard let box, let boxMesh else { return }

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

        guard let cylinderMesh else { return }

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
        guard let plane, let planeMesh else { return }

        var transform = transform

        // Scale the bounds of the plane to the model bounds
        if scaleToBounds, let bounds = context.vim.geometry?.bounds {
            transform.scale(bounds.extents)
        }

        // Set the plane position
        transform.position = plane.xyz * plane.w
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

        guard let sphereMesh else { return }

        // Draw the sphere using the sphere mesh
        drawShape(renderEncoder: renderEncoder, mesh: sphereMesh, color: color, transform: transform)
    }

    /// Makes all of the shape meshes
    private func makeMeshes() {

        let extents: SIMD3<Float> = .one

        self.allocator = MTKMeshBufferAllocator(device: device)
        let box = MDLMesh(boxWithExtent: extents, segments: .one, inwardNormals: false, geometryType: .triangles, allocator: allocator)
        let cylinder = MDLMesh(cylinderWithExtent: extents, segments: [50, 50], inwardNormals: false, topCap: false, bottomCap: false, geometryType: .triangles, allocator: allocator)
        let plane = MDLMesh(planeWithExtent: extents, segments: .one, geometryType: .triangles, allocator: allocator)
        let sphere = MDLMesh(sphereWithExtent: extents, segments: [50, 50], inwardNormals: false, geometryType: .triangles, allocator: allocator)

        guard let boxMesh = try? MTKMesh(mesh: box, device: device),
              let cylinderMesh = try? MTKMesh(mesh: cylinder, device: device),
              let planeMesh = try? MTKMesh(mesh: plane, device: device),
              let sphereMesh = try? MTKMesh(mesh: sphere, device: device) else { return }
        self.boxMesh = boxMesh
        self.cylinderMesh = cylinderMesh
        self.planeMesh = planeMesh
        self.sphereMesh = sphereMesh

    }

}
