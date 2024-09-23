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
    subscript(index: VertexBufferIndex) -> MTLPipelineBufferDescriptor {
        return self[index.rawValue]
    }
}
