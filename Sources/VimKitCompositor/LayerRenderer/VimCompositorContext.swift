//
//  VimCompositorContext.swift
//  
//
//  Created by Kevin McKee
//
#if os(visionOS)
import CompositorServices
import VimKit

public struct VimCompositorContext: VimRendererContext, VimRenderDestinationProvider {

    public let vim: Vim
    public let layerRenderer: LayerRenderer
    public var destinationProvider: VimRenderDestinationProvider {
        return self
    }

    let dataProviderContext: DataProviderContext

    public init(vim: Vim, layerRenderer: LayerRenderer, dataProviderContext: DataProviderContext) {
        self.vim = vim
        self.layerRenderer = layerRenderer
        self.dataProviderContext = dataProviderContext
    }

    /// Queries the device anchor at the specified timestamp
    /// - Parameter timestamp: the timestamp of the device to query for
    /// - Returns: the anchor at the specified timestamp
    public func queryDeviceAnchor(_ timestamp: TimeInterval = CACurrentMediaTime()) -> DeviceAnchor? {
        return dataProviderContext.queryDeviceAnchor(timestamp)
    }

    public var device: MTLDevice? {
        return layerRenderer.device
    }

    public var colorFormat: MTLPixelFormat {
        return layerRenderer.configuration.colorFormat
    }

    public var clearColor: MTLClearColor {
        return .skyBlue
    }

    public var depthFormat: MTLPixelFormat {
        return layerRenderer.configuration.depthFormat
    }

    public var viewCount: Int {
        return layerRenderer.properties.viewCount
    }

    public var currentRenderPassDescriptor: MTLRenderPassDescriptor? {
        return nil
    }

    public var currentDrawable: CAMetalDrawable? {
        return nil
    }
}

#endif
