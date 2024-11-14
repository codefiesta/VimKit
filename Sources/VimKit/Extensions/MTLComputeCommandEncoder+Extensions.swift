//
//  MTLComputeCommandEncoder+Extensions.swift
//  VimKit
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

extension MTLComputeCommandEncoder {

    /// Convenience method that sets the buffer and its offset using a known KernelBufferIndex.
    /// - Parameters:
    ///   - buffer: the metal buffer to set
    ///   - offset: the buffer offset
    ///   - index: the known kernel buffer index enum value
    func setBuffer(_ buffer: (any MTLBuffer)?, offset: Int, index: KernelBufferIndex) {
        setBuffer(buffer, offset: offset, index: index.rawValue)
    }

    /// Convenience method using KernelBufferIndex enum that sets the buffer data (by copy).
    /// - Parameters:
    ///   - bytes: the bytes to copy
    ///   - length: the byte length
    ///   - index: the known kernel buffer index enum value
    func setBytes(_ bytes: UnsafeRawPointer, length: Int, index: KernelBufferIndex) {
        setBytes(bytes, length: length, index: index.rawValue)
    }
}
