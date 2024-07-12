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

    public var vim: Vim?
    public var configuration: VimCompositorLayerConfiguration
    public var dataProviderContext: DataProviderContext

    /// Initializes the ImmersiveSpaceContent with the specified vim file, configuration, and data provider context.
    /// - Parameters:
    ///   - vim: the vim file to render
    ///   - configuration: the rendering configuration
    ///   - dataProviderContext: the data provider context that publishes events from ARKit hand + world tracking events.
    public init(vim: Vim?, configuration: VimCompositorLayerConfiguration, dataProviderContext: DataProviderContext) {
        self.vim = vim
        self.configuration = configuration
        self.dataProviderContext = dataProviderContext
    }

    // Provides our immersive scene content that uses Metal for drawing.
    // See: https://developer.apple.com/videos/play/wwdc2023/10089/
    // See: https://developer.apple.com/documentation/compositorservices/drawing_fully_immersive_content_using_metal
    public var body: some ImmersiveSpaceContent {
        CompositorLayer(configuration: configuration) { layerRenderer in
            guard let vim else { return }
            // Build our compositor context that provides all of the objects we need to render
            let compositorContext = VimCompositorContext(
                vim: vim,
                layerRenderer: layerRenderer,
                dataProviderContext: dataProviderContext
            )
            // Start the engine
            let engine = VimCompositorRenderer(compositorContext)
            engine.start()
        }
    }
}
#endif
