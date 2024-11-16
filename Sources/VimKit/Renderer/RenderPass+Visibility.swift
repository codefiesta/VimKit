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
    /// Combine subscribers.
    var subscribers = Set<AnyCancellable>()

    /// Initializes the render pass with the provided rendering context.
    /// - Parameter context: the rendering context.
    init(_ context: RendererContext) {
        self.context = context
        let options = context.vim.options
        let fragmentFunctionName = options.visualizeVisibilityResults ? functionNameFragment : nil
        let vertexDescriptor = makeVertexDescriptor()
        self.pipelineState = makeRenderPipelineState(context, vertexDescriptor, labelPipeline, functionNameVertexVisibilityTest, fragmentFunctionName)
        self.depthStencilState = makeDepthStencilState(isDepthWriteEnabled: options.visualizeVisibilityResults)
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
        drawGeometry(renderEncoder: renderEncoder)
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
              let materialsBuffer = geometry.materialsBuffer else { return }

        /// Configure the pipeline state object and depth state to disable writing to the color and depth attachments.
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(options.cullMode)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setTriangleFillMode(fillMode)

        // Setup the per frame buffers to pass to the GPU
        renderEncoder.setVertexBuffer(descriptor.framesBuffer, offset: descriptor.framesBufferOffset, index: .frames)
        renderEncoder.setVertexBuffer(positionsBuffer, offset: 0, index: .positions)
        renderEncoder.setVertexBuffer(normalsBuffer, offset: 0, index: .normals)
        renderEncoder.setVertexBuffer(instancesBuffer, offset: 0, index: .instances)
        renderEncoder.setVertexBuffer(materialsBuffer, offset: 0, index: .materials)
    }

    /// Draws simplified geometry for each instanced mesh.
    /// - Parameters:
    ///   - renderEncoder: the render encoder to use
    private func drawGeometry(renderEncoder: MTLRenderCommandEncoder) {

        // Don't perform the tests if the visibility result is disabled
        guard options.visibilityResults else { return }

        renderEncoder.pushDebugGroup(labelRenderEncoderDebugGroupName)

        for i in currentResults {
            drawGeometry(renderEncoder: renderEncoder, index: i)
        }
        renderEncoder.popDebugGroup()
    }

    /// Draws simplified proxy geometry for each instanced mesh.
    /// - Parameters:
    ///   - renderEncoder: the render encoder to use
    ///   - index: the index of the instanced mesh to test visibility results for
    private func drawGeometry(renderEncoder: MTLRenderCommandEncoder, index: Int) {

        guard let geometry, let materialsBuffer = geometry.materialsBuffer else { return }

        let instanced = geometry.instancedMeshes[index]
        let mesh = geometry.meshes[instanced.mesh]
        let submeshes = geometry.submeshes[mesh.submeshes]

        // Set the visibility result mode for the instanced mesh
        renderEncoder.setVisibilityResultMode(.boolean, offset: index * MemoryLayout<Int>.size)

        for (i, submesh) in submeshes.enumerated() {
            renderEncoder.pushDebugGroup("SubMesh[\(i)]")

            let offset = submesh.material * MemoryLayout<Material>.stride
            renderEncoder.setVertexBuffer(materialsBuffer, offset: offset, index: .materials)

            // Draw the submesh
            drawSubmesh(geometry, submesh, renderEncoder, instanced.instanceCount, instanced.baseInstance)
            renderEncoder.popDebugGroup()
        }
    }

    /// Draws the submesh using indexed primitives.
    /// - Parameters:
    ///   - geometry: the geometry
    ///   - submesh: the submesh
    ///   - renderEncoder: the render encoder to use
    ///   - instanceCount: the number of instances to draw.
    ///   - baseInstance: the offset for instance_id
    private func drawSubmesh(_ geometry: Geometry,
                             _ submesh: Submesh,
                             _ renderEncoder: MTLRenderCommandEncoder,
                             _ instanceCount: Int = 1,
                             _ baseInstance: Int = 0) {

        guard let indexBuffer = geometry.indexBuffer else { return }

        // TODO: This needs to be reworked to draw an LOD - we can't just use the bounding box
        // because the bounding box can extend over areas that it doesn't actually occupy and
        // mess up visibility results.
        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: submesh.indices.count,
                                            indexType: .uint32,
                                            indexBuffer: indexBuffer,
                                            indexBufferOffset: submesh.indexBufferOffset,
                                            instanceCount: instanceCount,
                                            baseVertex: 0,
                                            baseInstance: baseInstance
        )
    }

    /// Avoid a data race condition by updating the visibility buffer's read index when the command buffer finishes.
    private func didDraw() {
        visibilityBufferReadIndex = (visibilityBufferReadIndex + 1) % bufferCount
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

        if minFrustumCullingThreshold <= geometry.instancedMeshes.count {
            allResults = bvh.intersectionResults(camera: camera)
        } else {
            currentResults = Array(0..<geometry.instancedMeshes.count)
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
