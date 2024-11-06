//
//  VimImmersiveSpaceContent.swift
//
//
//

#if os(visionOS)
import CompositorServices
import SwiftUI
import VimKit

public struct VimImmersiveSpaceContent: ImmersiveSpaceContent {

    public var vim: Vim
    public var configuration: VimCompositorLayerConfiguration
    public var dataProvider: ARDataProvider

    /// Initializes the ImmersiveSpaceContent with the specified vim file, configuration, and data provider context.
    /// - Parameters:
    ///   - vim: the vim file to render
    ///   - configuration: the rendering configuration
    ///   - dataProvider: the ARKit data provider
    public init(vim: Vim, configuration: VimCompositorLayerConfiguration = .init(), dataProvider: ARDataProvider) {
        self.vim = vim
        self.configuration = configuration
        self.dataProvider = dataProvider
    }

    // Provides our immersive scene content that uses Metal for drawing.
    // See: https://developer.apple.com/videos/play/wwdc2023/10089/
    // See: https://developer.apple.com/documentation/compositorservices/drawing_fully_immersive_content_using_metal
    public var body: some ImmersiveSpaceContent {
        CompositorLayer(configuration: configuration) { layerRenderer in
            // Build our compositor context that provides all of the objects we need to render
            let compositorContext = VimCompositorContext(
                vim: vim,
                layerRenderer: layerRenderer,
                dataProvider: dataProvider
            )

            // Initiate the rendering engine
            _ = VimCompositorRenderer(compositorContext)
        }
    }
}
#endif
