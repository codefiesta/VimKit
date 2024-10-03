//
//  VimRendererContext.swift
//
//
//  Created by Kevin McKee
//

#if os(visionOS)
import CompositorServices
#endif
import MetalKit

@MainActor
public protocol VimRenderDestinationProvider {

    /// The Metal device used to interface with the GPU.
    var device: MTLDevice? { get }

    /// The pixel format to use for color textures.
    var colorFormat: MTLPixelFormat { get }

    /// The pixel format to use for depth textures.
    var depthFormat: MTLPixelFormat { get }

    /// The clear color value used to generate the render pass descriptor.
    var clearColor: MTLClearColor { get }

    /// The number of views that you must fill with content.
    var viewCount: Int { get }

    /// The current render pass descriptor.
    /// Only available if destination is MTKView.
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }

    /// The current drawable
    /// Only available if destination is MTKView.
    var currentDrawable: CAMetalDrawable? { get }
}

@MainActor
public protocol VimRendererContext {

    /// The vim file that provides the geometry data.
    var vim: Vim { get }

    /// The render destination provider
    var destinationProvider: VimRenderDestinationProvider { get }

    #if os(visionOS)

    /// The layer renderer the compsitor services uses.
    var layerRenderer: LayerRenderer { get }

    /// Queries the device anchor at the specified timestamp
    /// - Parameter timestamp: the timestamp of the device to query for
    /// - Returns: the anchor at the specified timestamp
    func queryDeviceAnchor(_ timestamp: TimeInterval) -> DeviceAnchor?
    #endif
}
