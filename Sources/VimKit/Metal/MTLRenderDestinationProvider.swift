//
//  MTLRenderDestinationProvider.swift
//
//
//  Created by Kevin McKee
//

import MetalKit

public protocol MTLRenderDestinationProvider {

    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var clearColor: MTLClearColor { get }
    var clearDepth: Double { get }
    var sampleCount: Int { get set }
    var desiredFrameInterval: TimeInterval { get }
    var device: MTLDevice? { get set }
}
