//
//  MTLRenderCommandEncoder+Extensions.swift
//
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

public extension MTLRenderCommandEncoder {

    /// Assigns a buffer to an entry in the vertex shader argument table using the buffer index.
    /// - Parameters:
    ///   - buffer: The metal buffer instance
    ///   - offset: An integer that represents the location, in bytes, from the start of buffer where the vertex shader argument data begins.
    ///   - index: The buffer index enum value
    func setVertexBuffer(_ buffer: MTLBuffer?, offset: Int, index: BufferIndex) {
        setVertexBuffer(buffer, offset: offset, index: index.rawValue)
    }

    // Convenience method using BufferIndex enum
    func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: BufferIndex) {
        setVertexBytes(bytes, length: length, index: index.rawValue)
    }

    // Convenience method using BufferIndex enum
    func setFragmentBuffer(_ buffer: MTLBuffer?, offset: Int, index: BufferIndex) {
        setFragmentBuffer(buffer, offset: offset, index: index.rawValue)
    }

    // Convenience method using BufferIndex enum
    func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: BufferIndex) {
        setFragmentBytes(bytes, length: length, index: index.rawValue)
    }
}
