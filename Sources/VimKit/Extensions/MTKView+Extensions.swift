//
//  MTKView+Extensions.swift
//  
//
//  Created by Kevin McKee
//

import MetalKit

#if !os(visionOS)

extension MTKView: VimRenderDestinationProvider {

    public var colorFormat: MTLPixelFormat { colorPixelFormat }

    public var depthFormat: MTLPixelFormat { depthStencilPixelFormat }

    public var viewCount: Int { 1 }
}

#endif
