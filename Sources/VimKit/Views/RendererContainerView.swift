//
//  RendererContainerView.swift
//
//
//  Created by Kevin McKee
//

import Combine
import MetalKit
import SwiftUI

#if !os(visionOS)
private struct RendererContainerViewContext: RendererContext {
    public var vim: Vim
    public var destinationProvider: RenderDestinationProvider
}

#if os(macOS)
private typealias ViewReprentable = NSViewRepresentable
private typealias GestureRecognizerType = NSClickGestureRecognizer
#else
private typealias ViewReprentable = UIViewRepresentable
private typealias GestureRecognizerType = UITapGestureRecognizer
#endif

/// Provides a UIViewRepresentable wrapper around an MTKView that is being driven by the `Renderer`.
public struct RendererContainerView: ViewReprentable {

#if os(macOS)
    public typealias NSViewType = MTKView
#else
    public typealias UIViewType = MTKView
#endif

    private var mtkView: MTKView = .init(frame: .zero)

    /// Provides the rendering context used to pass to the coordinator's renderer
    var renderContext: RendererContext

    public init(vim: Vim) {
        self.mtkView.device = MTLContext.device
        // Render Pass Descriptor Options
        self.mtkView.colorPixelFormat = .rgba16Float
        self.mtkView.depthStencilPixelFormat = .depth32Float_stencil8
        self.mtkView.clearColor = Color.skyBlueColor.mtlClearColor
        self.renderContext = RendererContainerViewContext(vim: vim, destinationProvider: mtkView)
    }

#if os(macOS)

    public func makeNSView(context: Context) -> MTKView {
        mtkView.delegate = context.coordinator
        addGestureRecognizers(mtkView, context: context)
        return mtkView
    }

    public func updateNSView(_ nsView: MTKView, context: Context) { }

#else

    public func makeUIView(context: Context) -> MTKView {
        mtkView.delegate = context.coordinator
        addGestureRecognizers(mtkView, context: context)
        return mtkView
    }

    public func updateUIView(_ mtkView: MTKView, context: Context) { }

#endif

    public func makeCoordinator() -> RendererContainerViewCoordinator {
        RendererContainerViewCoordinator(self)
     }

    /// Adds gesture recognizers to the metal view.
    /// - Parameter mtkView: the view to add gesture recognizers to
    private func addGestureRecognizers(_ mtkView: MTKView, context: Context) {

        let gesture: GestureRecognizerType = .init(
            target: context.coordinator,
            action: #selector(context.coordinator.handleTap(_:))
        )
        mtkView.addGestureRecognizer(gesture)
    }
}
#endif
