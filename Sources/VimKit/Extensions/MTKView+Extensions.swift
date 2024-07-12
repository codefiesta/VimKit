//
//  MTKView+Extensions.swift
//  
//
//  Created by Kevin McKee
//

import MetalKit

#if !os(visionOS)

private let instanceIndexTexture = "InstanceIndexTexture"

extension MTKView: VimRenderDestinationProvider {

    public var colorFormat: MTLPixelFormat {
        return colorPixelFormat
    }

    public var depthFormat: MTLPixelFormat {
        return depthStencilPixelFormat
    }

    public var viewCount: Int {
        return 1
    }
}

#endif
