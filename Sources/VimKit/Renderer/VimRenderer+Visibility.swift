//
//  VimRenderer+Visibility.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Combine
import MetalKit
import VimKitShaders

private let vertexFunctionName = "vertexVisibilityTest"
private let renderEncoderDebugGroupName = "VimVisibilityResultsDrawGroup"
private let pipelineLabel = "VimVisibilityResultsPipeline"
private let minFrustumCullingThreshold = 1024

extension VimRenderer {

    /// A class that culls occluded geometry by performing visibility testing.
    /// The render pass descriptor needs to have the visibilityResultBuffer value set in order to perform visibility tests.
    /// `renderPassDescriptor?.visibilityResultBuffer = visibility?.currentVisibilityResultBuffer`.
    ///
    /// [Culling occluded geometry using the visibility result buffer](https://developer.apple.com/documentation/metal/metal_sample_code_library/culling_occluded_geometry_using_the_visibility_result_buffer)
    @MainActor
    class Visibility {

        /// The context that provides all of the data we need
        let context: VimRendererContext

        /// Returns the rendering options.
        var options: Vim.Options {
            context.vim.options
        }

        /// The geometry.
        var geometry: Geometry? {
            context.vim.geometry
        }

        /// Returns the camera.
        var camera: Vim.Camera {
            context.vim.camera
        }

        /// The metal device.
        var device: MTLDevice {
            context.destinationProvider.device!
        }

        /// The number of rotating buffers.
        let bufferCount: Int
        /// A render pipeline that is used for occlusion queries with the depth test.
        let pipelineState: MTLRenderPipelineState?
        /// The depth stencil state that performs no writes for the non-rendering pipeline state.
        let depthStencilState: MTLDepthStencilState?

        /// The rotating visibility results buffers.
        var visibilityResultBuffer: [MTLBuffer?]
        var visibilityResultReadOnlyBuffer: UnsafeMutablePointer<Int>?
        var visibilityBufferReadIndex: Int = 0
        var visibilityBufferWriteIndex: Int = 0

        /// Combine Subscribers which drive rendering events
        var subscribers = Set<AnyCancellable>()

        /// Returns the current visibility result buffer write buffer.
        var currentVisibilityResultBuffer: MTLBuffer? {
            visibilityResultBuffer[visibilityBufferWriteIndex]
        }

        /// Returns the entire set of instanced mesh indexes that are inside the view frustum.
        var currentResults: [Int] = .init()

        /// Returns the subset of instanced mesh indexes that have returned true from the occlusion query.
        var currentVisibleResults: [Int] = .init()

        let mesh: MTKMesh

        /// Initializer.
        /// - Parameters:
        ///   - context: the renderer context
        ///   - bufferCount: the number of rotating buffers
        init?(_ context: VimRendererContext, bufferCount: Int) {

            guard let library = MTLContext.makeLibrary(),
                  let device = context.destinationProvider.device else { return nil }

            self.context = context
            self.bufferCount = bufferCount
            self.visibilityResultBuffer = [MTLBuffer?](repeating: nil, count: bufferCount)

            let options = context.vim.options

            // Create the proxy mesh to render (an icosahedron)
            let allocator = MTKMeshBufferAllocator(device: device)
            let proxyMesh = MDLMesh(boxWithExtent: .one, segments: .one, inwardNormals: false, geometryType: .triangles, allocator: allocator)
            guard let mesh = try? MTKMesh(mesh: proxyMesh, device: device) else { return nil }
            self.mesh = mesh

            let vertexFunction = library.makeFunction(name: vertexFunctionName)
            let fragmentFunction = library.makeFunction(name: "fragmentMain")

            let vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.label = pipelineLabel

            // Alpha Blending
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

            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = options.visualizeVisibilityResults ? fragmentFunction : nil
            pipelineDescriptor.vertexDescriptor = vertexDescriptor
            pipelineDescriptor.maxVertexAmplificationCount = context.destinationProvider.viewCount
            pipelineDescriptor.vertexBuffers[.positions].mutability = .mutable

            // Set the pipeline state with no rendering for the occlusion query
            pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor)

            // Set the depth stencil state for the occlusion query with no depth writes
            let depthStencilDescriptor = MTLDepthStencilDescriptor()
            depthStencilDescriptor.depthCompareFunction = .lessEqual
            depthStencilDescriptor.isDepthWriteEnabled = options.visualizeVisibilityResults
            depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)

            // Visibility Buffers
            buildVisibilityResultsBuffers()

            // Observe the geometry state
            context.vim.geometry?.$state.sink { [weak self] state in
                guard let self, let geometry else { return }
                switch state {
                case .indexing, .ready:
                    debugPrint("􀬨 Building visibility results buffers [\(geometry.instancedMeshes.count)]")
                    buildVisibilityResultsBuffers(geometry.instancedMeshes.count)
                case .loading, .unknown, .error:
                    break
                }
            }.store(in: &subscribers)

        }

        /// Builds the visibility results buffers array.
        /// - Parameters:
        ///   - objectCount: the total number of objects that can be checked for visibility.
        private func buildVisibilityResultsBuffers(_ objectCount: Int = 1) {
            for i in 0..<visibilityResultBuffer.count {
                let buffer = device.makeBuffer(length: MemoryLayout<Int>.size * objectCount, options: [.storageModeShared])
                buffer?.label = "VisibilityResultBuffer\(i)"
                visibilityResultBuffer[i] = buffer
            }
        }

        /// Performs an occulsion query by drawing (without rendering) proxy geomety to test if the results are visible or not.
        /// - Parameters:
        ///   - renderEncoder: the render encoder
        func draw(renderEncoder: MTLRenderCommandEncoder) {
            // Don't perform the tests if the visibility result is disabled
            guard options.visibilityResults, let pipelineState, let depthStencilState else { return }

            /// Configure the pipeline state object and depth state to disable writing to the color and depth attachments.
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setDepthStencilState(depthStencilState)
            renderEncoder.pushDebugGroup(renderEncoderDebugGroupName)

            for i in currentResults {
                drawProxyGeometry(renderEncoder: renderEncoder, index: i)
            }
            renderEncoder.popDebugGroup()

            // Finsh the frame and update the read index for the next frame
            finish()
        }

        /// Draws simplified proxy geometry for each instanced mesh.
        /// - Parameters:
        ///   - renderEncoder: the render encoder to use
        ///   - index: the index of the instanced mesh to test visibility results for
        func drawProxyGeometry(renderEncoder: MTLRenderCommandEncoder, index: Int) {

            guard let geometry else { return }

            let instanced = geometry.instancedMeshes[index]
            let instanceCount = instanced.instances.count
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

        /// Avoid a data race condition by updating the visibility buffer's read index when the command buffer finishes.
        private func finish() {
            visibilityBufferReadIndex = (visibilityBufferReadIndex + 1) % bufferCount
        }
    }
}
