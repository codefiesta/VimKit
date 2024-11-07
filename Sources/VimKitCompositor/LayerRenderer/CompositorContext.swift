//
//  CompositorContext.swift
//  
//
//  Created by Kevin McKee
//
#if os(visionOS)
import CompositorServices
import SwiftUI
import VimKit

public struct CompositorContext: RendererContext, RenderDestinationProvider {

    public let vim: Vim
    public let layerRenderer: LayerRenderer
    public var destinationProvider: RenderDestinationProvider {
        self
    }

    let dataProvider: ARDataProvider

    public init(vim: Vim, layerRenderer: LayerRenderer, dataProvider: ARDataProvider) {
        self.vim = vim
        self.layerRenderer = layerRenderer
        self.dataProvider = dataProvider
    }

    /// Queries the device anchor at the specified timestamp
    /// - Parameter timestamp: the timestamp of the device to query for
    /// - Returns: the anchor at the specified timestamp
    public func queryDeviceAnchor(_ timestamp: TimeInterval = CACurrentMediaTime()) -> DeviceAnchor? {
        dataProvider.queryDeviceAnchor(timestamp)
    }

    public var device: MTLDevice? {
        layerRenderer.device
    }

    public var colorFormat: MTLPixelFormat {
        layerRenderer.configuration.colorFormat
    }

    public var clearColor: MTLClearColor {
        Color.skyBlueColor.mtlClearColor
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
