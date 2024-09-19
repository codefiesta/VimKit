//
//  VimContainerView.swift
//
//
//  Created by Kevin McKee
//

import Combine
import MetalKit
import SwiftUI

#if os(iOS)

private struct VimContainerViewRendererContext: VimRendererContext {

    public var vim: Vim
    public var destinationProvider: VimRenderDestinationProvider
}

/// Provides a UIViewRepresentable wrapper around a MTKView
public struct VimContainerView: UIViewRepresentable {

    public typealias UIViewType = MTKView
    private var mtkView: MTKView = .init(frame: .zero)

    /// Provides the rendering context used to pass to the coordinator's renderer
    var renderContext: VimRendererContext

    public init(vim: Vim) {
        self.mtkView.device = MTLContext.device
        self.mtkView.backgroundColor = .clear
        // Render Pass Descriptor Options
        self.mtkView.colorPixelFormat = .rgba16Float
        self.mtkView.depthStencilPixelFormat = .depth32Float_stencil8
        self.mtkView.clearColor = Color.skyBlue.mtlClearColor
        self.renderContext = VimContainerViewRendererContext(vim: vim, destinationProvider: mtkView)
    }

    public func makeUIView(context: Context) -> MTKView {
        mtkView.delegate = context.coordinator
        // Gesture recognizers
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(context.coordinator.handleTap(_:))
        )
        mtkView.addGestureRecognizer(tapGesture)
        return mtkView
    }

    public func updateUIView(_ mtkView: MTKView, context: Context) {

    }

    public func makeCoordinator() -> VimContainerViewCoordinator {
        VimContainerViewCoordinator(self)
     }
}

#endif
