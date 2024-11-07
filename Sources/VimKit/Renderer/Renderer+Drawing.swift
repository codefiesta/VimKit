//
//  Renderer+Drawing.swift
//
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

///  The render encoder label.
private let renderEncoderLabel = "VimRenderEncoder"
///  The render encoder debug group.
private let renderEncoderDebugGroupName = "VimDrawGroup"
///  The minimum amount of instanced meshes to implement frustum culling.
private let minFrustumCullingThreshold = 1024

#if !os(visionOS)

extension Renderer: MTKViewDelegate {

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let isLandscape = size.height < size.width
        let aspectRatio = isLandscape ? Float(size.width/size.height) : Float(size.height/size.width)
        context.vim.camera.aspectRatio = aspectRatio
        viewportSize = [Float(size.width), Float(size.height)]
    }

    public func draw(in view: MTKView) {
        renderNewFrame()
    }
}

#endif

public extension Renderer {

    /// Renders a new frame.
    private func renderNewFrame() {

        // Prepare the render pass descriptor
        buildRenderPassDescriptor()

        guard let geometry, geometry.state == .ready else { return }
        guard let renderPassDescriptor,
              let drawable = context.destinationProvider.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Update the per-frame state
        updatFrameState()

        if supportsIndirectCommandBuffers {
            drawIndirect(commandBuffer: commandBuffer)
        } else {

            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
            renderEncoder.label = renderEncoderLabel


            // Perform any pre scene draws
            willDrawScene(renderEncoder: renderEncoder)
            // Draw the scene
            drawScene(renderEncoder: renderEncoder, commandBuffer: commandBuffer)

            // Perform any post scene draws
            didDrawScene(renderEncoder: renderEncoder)

            renderEncoder.endEncoding()
        }


        // Schedule the presentation and commit
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Performs any draws before the scene draw.
    /// - Parameter renderEncoder: the render encoder
    func willDrawScene(renderEncoder: MTLRenderCommandEncoder) {
        guard let geometry,
              let pipelineState,
              let positionsBuffer = geometry.positionsBuffer,
              let normalsBuffer = geometry.normalsBuffer,
              let instancesBuffer = geometry.instancesBuffer,
              let submeshesBuffer = geometry.submeshesBuffer,
              let colorsBuffer = geometry.colorsBuffer else { return }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setCullMode(options.cullMode)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setTriangleFillMode(fillMode)

        // Setup the per frame buffers to pass to the GPU
        renderEncoder.setVertexBuffer(uniformBuffer, offset: uniformBufferOffset, index: .uniforms)
        renderEncoder.setVertexBuffer(positionsBuffer, offset: 0, index: .positions)
        renderEncoder.setVertexBuffer(normalsBuffer, offset: 0, index: .normals)
        renderEncoder.setVertexBuffer(instancesBuffer, offset: 0, index: .instances)
        renderEncoder.setVertexBuffer(submeshesBuffer, offset: 0, index: .submeshes)
        renderEncoder.setVertexBuffer(colorsBuffer, offset: 0, index: .colors)
        renderEncoder.setFragmentTexture(baseColorTexture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)

        // Set the per frame render options
        var options = RenderOptions(xRay: xRayMode)
        renderEncoder.setVertexBytes(&options, length: MemoryLayout<RenderOptions>.size, index: .renderOptions)
    }

    /// Draws the entire scene.
    /// - Parameters:
    ///   - renderEncoder: the render encoder
    ///   - commandBuffer: the command buffer
    func drawScene(renderEncoder: MTLRenderCommandEncoder, commandBuffer: MTLCommandBuffer) {

        guard let geometry else { return }

        renderEncoder.pushDebugGroup(renderEncoderDebugGroupName)

        let results = visibility?.currentVisibleResults ?? .init()
        let start = Date.now

        // Draw the instanced meshes
        for i in results {
            guard abs(start.timeIntervalSinceNow) < frameTimeLimit else { break }
            let instanced = geometry.instancedMeshes[i]
            drawInstanced(instanced, renderEncoder: renderEncoder)
        }
        renderEncoder.popDebugGroup()
    }


    /// Performs indirect drawing by using the indirect command buffer to encode the drawing commands on the GPU.
    /// - Parameters:
    ///   - renderEncoder: the render encoder
    ///   - commandBuffer: the command buffer
    private func drawIndirect(commandBuffer: MTLCommandBuffer) {
        guard let geometry,
              let computePipelineState,
              let icb,
              let icbBuffer,
              let positionsBuffer = geometry.positionsBuffer,
              let normalsBuffer = geometry.normalsBuffer,
              let indexBuffer = geometry.indexBuffer,
              let instancesBuffer = geometry.instancesBuffer,
              let instancedMeshesBuffer = geometry.instancedMeshesBuffer,
              let meshesBuffer = geometry.meshesBuffer,
              let submeshesBuffer = geometry.submeshesBuffer,
              let materialsBuffer = geometry.materialsBuffer,
              let colorsBuffer = geometry.colorsBuffer,
              let visibilityResults = visibility?.currentVisibilityResultBuffer,
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { return }

        // 1) Encode
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setBuffer(uniformBuffer, offset: uniformBufferOffset, index: .uniforms)
        computeEncoder.setBuffer(positionsBuffer, offset: 0, index: .positions)
        computeEncoder.setBuffer(normalsBuffer, offset: 0, index: .normals)
        computeEncoder.setBuffer(indexBuffer, offset: 0, index: .indexBuffer)
        computeEncoder.setBuffer(instancesBuffer, offset: 0, index: .instances)
        computeEncoder.setBuffer(instancedMeshesBuffer, offset: 0, index: .instancedMeshes)
        computeEncoder.setBuffer(meshesBuffer, offset: 0, index: .meshes)
        computeEncoder.setBuffer(submeshesBuffer, offset: 0, index: .submeshes)
        computeEncoder.setBuffer(materialsBuffer, offset: 0, index: .materials)
        computeEncoder.setBuffer(colorsBuffer, offset: 0, index: .colors)
        computeEncoder.setBuffer(visibilityResults, offset: 0, index: .visibilityResults)
        computeEncoder.setBuffer(icbBuffer, offset: 0, index: .commandBufferContainer)

        var options = RenderOptions(xRay: xRayMode)
        computeEncoder.setBytes(&options, length: MemoryLayout<RenderOptions>.size, index: .renderOptions)

        // 2) Use Resources
        computeEncoder.useResource(icb, usage: .write)
        computeEncoder.useResource(uniformBuffer, usage: .read)
        computeEncoder.useResource(visibilityResults, usage: .read)
        computeEncoder.useResource(materialsBuffer, usage: .read)
        computeEncoder.useResource(instancesBuffer, usage: .read)
        computeEncoder.useResource(instancedMeshesBuffer, usage: .read)
        computeEncoder.useResource(meshesBuffer, usage: .read)
        computeEncoder.useResource(submeshesBuffer, usage: .read)
        computeEncoder.useResource(meshesBuffer, usage: .read)
        computeEncoder.useResource(indexBuffer, usage: .write)

        // 3) Dispatch the threads
        let drawCount = geometry.instancedMeshes.count
        let gridSize: MTLSize = .init(width: drawCount, height: 1, depth: 1)
        let threadExecutionWidth = computePipelineState.threadExecutionWidth
        let threadgroupSize: MTLSize = .init(width: threadExecutionWidth, height: 1, depth: 1)
        computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)

        // 4) End Encoding
        computeEncoder.endEncoding()

        let range = 0..<drawCount

        guard let renderPassDescriptor, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        renderEncoder.label = renderEncoderLabel

        willDrawScene(renderEncoder: renderEncoder)
        renderEncoder.executeCommandsInBuffer(icb, range: range)
        didDrawScene(renderEncoder: renderEncoder)

        renderEncoder.endEncoding()
    }

    /// Performs any draws after the main scene draw.
    /// - Parameters:
    ///   - renderEncoder: the render encoder
    func didDrawScene(renderEncoder: MTLRenderCommandEncoder) {
        skycube?.draw(renderEncoder: renderEncoder, uniformBuffer: uniformBuffer, uniformBufferOffset: uniformBufferOffset, samplerState: samplerState)
        visibility?.draw(renderEncoder: renderEncoder)
    }

    /// Draws an instanced mesh.
    /// - Parameters:
    ///   - instanced: the instanced mesh to draw
    ///   - renderEncoder: the render encoder
    private func drawInstanced(_ instanced: InstancedMesh, renderEncoder: MTLRenderCommandEncoder) {
        guard let geometry, let materialsBuffer = geometry.materialsBuffer else { return }
        let mesh = geometry.meshes[instanced.mesh]
        let submeshes = geometry.submeshes[mesh.submeshes]
        for (i, submesh) in submeshes.enumerated() {
            guard submesh.material != .empty else { continue }

            renderEncoder.pushDebugGroup("SubMesh[\(i)]")

            let offset = MemoryLayout<Material>.stride * submesh.material// *
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
}
