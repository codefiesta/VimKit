//
//  MTLVertexDescriptor+Extensions.swift
//  VimKit
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

public extension MTLVertexAttributeDescriptorArray {

    // Convenience subscript using VertexAttribute enum
    subscript(index: VertexAttribute) -> MTLVertexAttributeDescriptor! {
        return self[index.rawValue]
    }
}

public extension MTLVertexBufferLayoutDescriptorArray {

    // Convenience subscript using BufferIndex enum
    subscript(index: BufferIndex) -> MTLVertexBufferLayoutDescriptor! {
        return self[index.rawValue]
    }
}
