//
//  Renderer+Metal.swift
//  
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

private let labelInstancePickingTexture = "InstancePickingTexture"
private let labelRasterizationRateMap = "RenderRasterizationMap"
private let labelRasterizationRateMapData = "RenderRasterizationMapData"

extension Renderer {

    /// Builds a render pass descriptor from the destination provider's (MTKView) current render pass descriptor.
    /// - Parameters:
    ///   - visibilityResultBuffer: the visibility result write buffer
    func makeRenderPassDescriptor(_ visibilityResultBuffer: MTLBuffer? = nil) -> MTLRenderPassDescriptor? {

        // Use the render pass descriptor from the MTKView
        let renderPassDescriptor = context.destinationProvider.currentRenderPassDescriptor

        // Instance Picking Texture Attachment
        renderPassDescriptor?.colorAttachments[1].texture = instancePickingTexture
        renderPassDescriptor?.colorAttachments[1].loadAction = .clear
        renderPassDescriptor?.colorAttachments[1].storeAction = .store

        // Depth attachment
        renderPassDescriptor?.depthAttachment.clearDepth = 1.0

        // Visibility Results
        renderPassDescriptor?.visibilityResultBuffer = visibilityResultBuffer
        return renderPassDescriptor
    }

    /// Handles view resize.
    func resize() {
        // Update the camera
        camera.viewportSize = viewportSize

        // Rebuild the textures.
        makeTextures()

        // Make the rasterizarion map data
        makeRasterizationMap()

        // Inform the render passes that the view has been resized
        for (i, _) in renderPasses.enumerated() {
            renderPasses[i].resize(viewportSize: viewportSize, physicalSize: physicalSize)
        }
    }

    /// Makes the textures when the viewport size changes.
    func makeTextures() {

        guard viewportSize != .zero else { return }

        let width = Int(viewportSize.x)
        let height = Int(viewportSize.y)

        // Instance Picking Texture
        let instancePickingTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Sint, width: width, height: height, mipmapped: false)
        instancePickingTextureDescriptor.usage = .renderTarget

        instancePickingTexture = device.makeTexture(descriptor: instancePickingTextureDescriptor)
        instancePickingTexture?.label = labelInstancePickingTexture
    }

    /// Makes the rasterization map data.
    private func makeRasterizationMap() {

        guard viewportSize != .zero else { return }
        let screenSize: MTLSize = .init(width: Int(viewportSize.x), height: Int(viewportSize.y), depth: .zero)
        let quality: [Float] = [0.3, 0.6, 1.0, 0.6, 0.3]
        let sampleCount: MTLSize = .init(width: 5, height: 5, depth: 0)
        let layerDescriptor: MTLRasterizationRateLayerDescriptor = .init(horizontal: quality, vertical: quality)
        layerDescriptor.sampleCount = sampleCount

        let rasterizationRateMapDescriptor: MTLRasterizationRateMapDescriptor = .init(screenSize: screenSize, layer: layerDescriptor, label: labelRasterizationRateMap)

        guard let rasterizationRateMap = device.makeRasterizationRateMap(descriptor: rasterizationRateMapDescriptor) else { return }

        self.rasterizationRateMap = rasterizationRateMap
        let bufferLength = rasterizationRateMap.parameterDataSizeAndAlign.size
        guard let rasterizationRateMapData = device.makeBuffer(length: bufferLength, options: []) else { return }
        rasterizationRateMapData.label = labelRasterizationRateMapData

        self.rasterizationRateMapData = rasterizationRateMapData
        rasterizationRateMap.copyParameterData(buffer: rasterizationRateMapData, offset: 0)

        let physicalSize = rasterizationRateMap.physicalSize(layer: 0)
        self.physicalSize = .init(Float(physicalSize.width), Float(physicalSize.height))
    }
}
