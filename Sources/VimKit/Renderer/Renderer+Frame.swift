//
//  Renderer+Frame.swift
//  VimKit
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

extension Renderer {
    /// Struct containing the data for each frame. Multiple copies exist to allow updating while others are in flight.
    struct Frame {

        ///  A metal buffer of FrameUniforms.
        let uniforms: MTLBuffer
    }

}
