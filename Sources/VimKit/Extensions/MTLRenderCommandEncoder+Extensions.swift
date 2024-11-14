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
    ///   - index: The vertex buffer index enum value
    func setVertexBuffer(_ buffer: MTLBuffer?, offset: Int, index: VertexBufferIndex) {
        setVertexBuffer(buffer, offset: offset, index: index.rawValue)
    }

    /// Convenience method using VertexBufferIndex enum that sets the buffer data (by copy).
    /// - Parameters:
    ///   - bytes: the bytes to copy
    ///   - length: the byte length
    ///   - index: The buffer index enum value
    func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: VertexBufferIndex) {
        setVertexBytes(bytes, length: length, index: index.rawValue)
    }

    /// Convenience method using BufferIndex enum that set a global buffer for all fragment shaders at the given bind point index.
    /// - Parameters:
    ///   - buffer: the metal buffer
    ///   - offset: the buffer offset
    ///   - index: The kernel buffer index enum value
    func setFragmentBuffer(_ buffer: MTLBuffer?, offset: Int, index: KernelBufferIndex) {
        setFragmentBuffer(buffer, offset: offset, index: index.rawValue)
    }
//
//    //
//    /// Convenience method using BufferIndex enum that sets the buffer data (by copy).
//    /// - Parameters:
//    ///   - bytes: the bytes to copy
//    ///   - length: the byte length
//    ///   - index: The buffer index enum value
//    func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: BufferIndex) {
//        setFragmentBytes(bytes, length: length, index: index.rawValue)
//    }
}
