//
//  RenderPass+Visibility.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Combine
import MetalKit
import VimKitShaders

private let functionNameVertexVisibilityTest = "vertexVisibilityTest"
private let functionNameFragment = "fragmentMain"
private let labelRenderEncoderDebugGroupName = "VisibilityResults"
private let labelPipeline = "RenderPassVisibilityPipeline"
private let labelRenderEncoder = "RenderEncoderVisibility"
private let minFrustumCullingThreshold = 1024

/// A class that culls occluded geometry by performing visibility testing.
/// The render pass descriptor needs to have the visibilityResultBuffer value set in order to perform visibility tests.
/// `renderPassDescriptor?.visibilityResultBuffer = visibility?.currentVisibilityResultBuffer`.
///
/// [Culling occluded geometry using the visibility result buffer](https://developer.apple.com/documentation/metal/metal_sample_code_library/culling_occluded_geometry_using_the_visibility_result_buffer)
class RenderPassVisibility: RenderPass {

    /// The context that provides all of the data we need
    let context: RendererContext
    /// The number of rotating buffers.
    var bufferCount: Int = 4
    /// A render pipeline that is used for occlusion queries with the depth test.
    var pipelineState: MTLRenderPipelineState?
    /// The depth stencil state that performs no writes for the non-rendering pipeline state.
    var depthStencilState: MTLDepthStencilState?

    /// The rotating visibility results buffers.
    var visibilityResultBuffer = [MTLBuffer?]()
    var visibilityResultReadOnlyBuffer: UnsafeMutablePointer<Int>?
    var visibilityBufferReadIndex: Int = 0
    var visibilityBufferWriteIndex: Int = 0

    /// Returns the current visibility result buffer write buffer.
    var currentVisibilityResultBuffer: MTLBuffer? {
        visibilityResultBuffer[visibilityBufferWriteIndex]
    }
    /// Returns the entire set of instanced mesh indexes that are inside the view frustum.
    var currentResults: [Int] = .init()
    /// Returns the subset of instanced mesh indexes that have returned true from the occlusion query.
    var currentVisibleResults: [Int] = .init()
    /// The proxy mesh to draw.
    var mesh: MTKMesh?
    /// Combine Subscribers which drive rendering events
    var subscribers = Set<AnyCancellable>()

    /// Initializes the render pass with the provided rendering context.
    /// - Parameter context: the rendering context.
    init(_ context: RendererContext) {
        self.context = context
        let options = context.vim.options
        let fragmentFunctionName = options.visualizeVisibilityResults ? functionNameFragment : nil
        let vertexDescriptor = makeVertexDescriptor()
        self.pipelineState = makeRenderPipelineState(context, vertexDescriptor, labelPipeline, functionNameVertexVisibilityTest, fragmentFunctionName)
        self.depthStencilState = makeDepthStencilState(.less, options.visualizeVisibilityResults)
        self.mesh = makeMesh()
        self.visibilityResultBuffer = [MTLBuffer?](repeating: nil, count: bufferCount)

        // Visibility Buffers
        makeVisibilityResultsBuffers()

        // Observe the geometry state
        context.vim.geometry?.$state.sink { [weak self] state in
            guard let self, let geometry else { return }
            switch state {
            case .indexing, .ready:
                debugPrint("􀬨 Building visibility results buffers [\(geometry.instancedMeshes.count)]")
                makeVisibilityResultsBuffers(geometry.instancedMeshes.count)
            case .loading, .unknown, .error:
                break
            }
        }.store(in: &subscribers)
    }

    /// Performs a draw call with the specified command buffer and render pass descriptor.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    func draw(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {
        // Encode the buffers
        encode(descriptor: descriptor, renderEncoder: renderEncoder)

        // Make the draw calls
        drawProxyGeometry(renderEncoder: renderEncoder)
    }

    /// Encodes the buffer data into the render encoder.
    /// - Parameters:
    ///   - descriptor: the draw descriptor to use
    ///   - renderEncoder: the render encoder to use
    private func encode(descriptor: DrawDescriptor, renderEncoder: MTLRenderCommandEncoder) {
        guard let geometry,
              let pipelineState,
              let positionsBuffer = geometry.positionsBuffer,
              let normalsBuffer = geometry.normalsBuffer,
              let instancesBuffer = geometry.instancesBuffer,
              let submeshesBuffer = geometry.submeshesBuffer,
              let materialsBuffer = geometry.materialsBuffer else { return }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(options.cullMode)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setTriangleFillMode(fillMode)

        // Setup the per frame buffers to pass to the GPU
        renderEncoder.setVertexBuffer(descriptor.uniformsBuffer, offset: descriptor.uniformsBufferOffset, index: .uniforms)
        renderEncoder.setVertexBuffer(positionsBuffer, offset: 0, index: .positions)
        renderEncoder.setVertexBuffer(normalsBuffer, offset: 0, index: .normals)
        renderEncoder.setVertexBuffer(instancesBuffer, offset: 0, index: .instances)
        renderEncoder.setVertexBuffer(submeshesBuffer, offset: 0, index: .submeshes)
        renderEncoder.setVertexBuffer(materialsBuffer, offset: 0, index: .materials)
    }

    /// Draws simplified proxy geometry for each instanced mesh.
    /// - Parameters:
    ///   - renderEncoder: the render encoder to use
    private func drawProxyGeometry(renderEncoder: MTLRenderCommandEncoder) {

        // Don't perform the tests if the visibility result is disabled
        guard options.visibilityResults, let pipelineState, let depthStencilState else { return }

        /// Configure the pipeline state object and depth state to disable writing to the color and depth attachments.
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.pushDebugGroup(labelRenderEncoderDebugGroupName)

        for i in currentResults {
            drawProxyGeometry(renderEncoder: renderEncoder, index: i)
        }
        renderEncoder.popDebugGroup()
    }

    /// Draws simplified proxy geometry for each instanced mesh.
    /// - Parameters:
    ///   - renderEncoder: the render encoder to use
    ///   - index: the index of the instanced mesh to test visibility results for
    private func drawProxyGeometry(renderEncoder: MTLRenderCommandEncoder, index: Int) {

        guard let geometry, let mesh else { return }

        let instanced = geometry.instancedMeshes[index]
        let instanceCount = instanced.instanceCount
        let baseInstance = instanced.baseInstance

        // Set the visibility result mode for the instanced mesh
        renderEncoder.setVisibilityResultMode(.boolean, offset: index * MemoryLayout<Int>.size)
        renderEncoder.setVertexBuffer(mesh.vertexBuffers.first?.buffer, offset: 0, index: .positions)

        // Draw the mesh
        for submesh in mesh.submeshes {
            renderEncoder.drawIndexedPrimitives(
                type: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer.buffer,
                indexBufferOffset: submesh.indexBuffer.offset,
                instanceCount: instanceCount,
                baseVertex: 0,
                baseInstance: baseInstance
            )
        }
    }

    /// Avoid a data race condition by updating the visibility buffer's read index when the command buffer finishes.
    private func didDraw() {
        visibilityBufferReadIndex = (visibilityBufferReadIndex + 1) % bufferCount
    }

    /// Makes the proxy mesh.
    /// - Returns: the proxy mesh to use for visibility testing.
    private func makeMesh() -> MTKMesh? {
        let allocator = MTKMeshBufferAllocator(device: device)
        let proxyMesh = MDLMesh(boxWithExtent: .one, segments: .one, inwardNormals: false, geometryType: .triangles, allocator: allocator)
        return try? MTKMesh(mesh: proxyMesh, device: device)
    }

    /// Builds the visibility results buffers array.
    /// - Parameters:
    ///   - objectCount: the total number of objects that can be checked for visibility.
    private func makeVisibilityResultsBuffers(_ objectCount: Int = 1) {
        for i in 0..<visibilityResultBuffer.count {
            let buffer = device.makeBuffer(length: MemoryLayout<Int>.size * objectCount, options: [.storageModeShared])
            buffer?.label = "VisibilityResultBuffer\(i)"
            visibilityResultBuffer[i] = buffer
        }
    }

    /// Updates the visibility buffer read results from the previous frame.
    func updateFrameState() {
        // Rotate the write index
        visibilityBufferWriteIndex = (visibilityBufferWriteIndex + 1) % bufferCount
        // Update the current read only buffer
        visibilityResultReadOnlyBuffer = visibilityResultBuffer[visibilityBufferReadIndex]?.contents().assumingMemoryBound(to: Int.self)

        // Update the entire set of current results
        var allResults = Set<Int>()
        var visibleResults = Set<Int>()
        guard let geometry, let bvh = geometry.bvh else { return }

        if minFrustumCullingThreshold <= geometry.instancedMeshes.endIndex {
            allResults = bvh.intersectionResults(camera: camera)
        } else {
            currentResults = Set(geometry.instancedMeshes.indices).sorted()
            currentVisibleResults = currentResults
            return
        }

        // Update the set of visible results
        currentResults = allResults.sorted()

        // If we are visualizing the visibility results, don't provide any results to the main render pass
        if options.visualizeVisibilityResults { return }

        // If visibility results are turned on, filter the results from the read only buffer
        visibleResults = options.visibilityResults ?
            allResults.filter { visibilityResultReadOnlyBuffer?[$0] != .zero } : allResults
        currentVisibleResults = visibleResults.sorted()

    }
}
