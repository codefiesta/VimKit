//
//  CompositorRendererConfiguration.swift
//  VimViewer
//
//  Created by Kevin McKee
//

#if os(visionOS)
import CompositorServices
import SwiftUI

@MainActor
public struct CompositorRendererConfiguration: CompositorLayerConfiguration {

    public init() { }

    public func makeConfiguration(capabilities: LayerRenderer.Capabilities, configuration: inout LayerRenderer.Configuration) {

        let supportsFoveation = capabilities.supportsFoveation
        let supportedLayouts = capabilities.supportedLayouts(options: supportsFoveation ? [.foveationEnabled] : [])

        configuration.layout = supportedLayouts.contains(.layered) ? .layered : .dedicated
        configuration.isFoveationEnabled = supportsFoveation

        // Color Format
        if capabilities.supportedColorFormats.contains(.rgba16Float) {
            configuration.colorFormat = .rgba16Float
        }

        // Depth Format
        if capabilities.supportedDepthFormats.contains(.depth32Float_stencil8) {
            configuration.depthFormat = .depth32Float_stencil8
        }
    }
}
#endif
