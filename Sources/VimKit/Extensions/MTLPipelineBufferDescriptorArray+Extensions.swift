//
//  MTLPipelineBufferDescriptorArray+Extensions.swift
//
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

public extension MTLPipelineBufferDescriptorArray {

    // Convenience subscript using BufferIndex enum
    subscript(index: BufferIndex) -> MTLPipelineBufferDescriptor {
        return self[index.rawValue]
    }
}
