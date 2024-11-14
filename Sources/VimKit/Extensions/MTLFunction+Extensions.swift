//
//  MTLFunction+Extensions.swift
//  VimKit
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

extension MTLFunction {

    /// Convenience method using KernelBufferIndex enum that makes an argument encoder.
    /// - Parameter index: the kernel buffer index
    /// - Returns: an argument encoder
    func makeArgumentEncoder(_ index: KernelBufferIndex) -> any MTLArgumentEncoder {
        makeArgumentEncoder(bufferIndex: index.rawValue)
    }

}
