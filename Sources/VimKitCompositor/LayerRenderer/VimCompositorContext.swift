//
//  VimCompositorContext.swift
//  
//
//  Created by Kevin McKee
//
#if os(visionOS)
import CompositorServices
import SwiftUI
import VimKit

public struct VimCompositorContext: VimRendererContext, VimRenderDestinationProvider {

    public let vim: Vim
    public let layerRenderer: LayerRenderer
    public var destinationProvider: VimRenderDestinationProvider {
        self
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
        dataProviderContext.queryDeviceAnchor(timestamp)
    }

    public var device: MTLDevice? {
        layerRenderer.device
    }

    public var colorFormat: MTLPixelFormat {
        layerRenderer.configuration.colorFormat
    }

    public var clearColor: MTLClearColor {
        Color.skyBlue.mtlClearColor
    }

    public var depthFormat: MTLPixelFormat {
        layerRenderer.configuration.depthFormat
    }

    public var viewCount: Int {
        layerRenderer.properties.viewCount
    }

    public var currentRenderPassDescriptor: MTLRenderPassDescriptor? {
        nil
    }

    public var currentDrawable: CAMetalDrawable? {
        nil
    }
}

#endif
