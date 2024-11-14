//
//  MTLArgumentEncoder+Extensions.swift
//  VimKit
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

extension MTLArgumentEncoder {

    /// Convenience method that sets the indirect command buffer using an ArgumentBufferIndex.
    /// - Parameters:
    ///   - indirectCommandBuffer: the indirect command buffer to set
    ///   - index: the ArgumentBufferIndex
    func setIndirectCommandBuffer(_ indirectCommandBuffer: (any MTLIndirectCommandBuffer)?, index: ArgumentBufferIndex) {
        setIndirectCommandBuffer(indirectCommandBuffer, index: index.rawValue)
    }
}

