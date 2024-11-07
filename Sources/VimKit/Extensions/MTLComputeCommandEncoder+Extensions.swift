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
    ///   - index: the known KernelBufferIndex
    func setBuffer(_ buffer: (any MTLBuffer)?, offset: Int, index: KernelBufferIndex) {
        setBuffer(buffer, offset: offset, index: index.rawValue)
    }
    
    func setBytes(_ bytes: UnsafeRawPointer, length: Int, index: KernelBufferIndex) {
        setBytes(bytes, length: length, index: index.rawValue)
    }
}
