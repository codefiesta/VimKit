//
//  Renderer+Delegate.swift
//  VimKit
//
//  Created by Kevin McKee
//

import MetalKit

/// A protocol that can be used for rendering responsibilities.
@MainActor
public protocol RenderingDelegate: AnyObject {

    /// Provides access to an instance picking texture.
    var instancePickingTexture: MTLTexture? { get }
}
