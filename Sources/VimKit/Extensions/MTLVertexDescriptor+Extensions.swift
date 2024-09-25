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
        self[index.rawValue]
    }
}

public extension MTLVertexBufferLayoutDescriptorArray {

    // Convenience subscript using BufferIndex enum
    subscript(index: VertexBufferIndex) -> MTLVertexBufferLayoutDescriptor! {
        self[index.rawValue]
    }
}
