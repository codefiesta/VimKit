//
//  MTLDevice+Extensions.swift
//  
//
//  Created by Kevin McKee
//

import Foundation
import MetalKit

public extension MTLDevice {

    /// Attempts to create a MTLBuffer by copying the bytes from the specified data block.
    /// - Parameters:
    ///   - data: The data block that holds the bytes to copy the bytes from.
    ///   - type: The underlying data type of the data block
    /// - Returns: A new buffer by copying the existing data into it.
    func makeBuffer<T>(_ data: Data, type: T.Type) -> MTLBuffer? {
        let byteCount = data.count
        let capacity = Int(byteCount / MemoryLayout<T>.size)
        let buffer: MTLBuffer? = data.withUnsafeBytes { pointer in
            guard let rawPointer = pointer.baseAddress?.bindMemory(to: type, capacity: capacity) else { return nil }
            return makeBuffer(bytes: rawPointer, length: byteCount)
        }
        return buffer
    }

    /// Attempts to create a MTLBuffer using the specified data.
    /// - Parameters:
    ///   - data: The data block that holds the bytes.
    ///   - label: the buffer label
    ///   - type: The underlying data type of the data block
    /// - Returns: A  new metal buffer that wraps an existing contiguous memory allocation.
    func makeBufferNoCopy<T>(_ data: inout Data, _ label: String? = nil, type: T.Type) -> MTLBuffer? {
        let byteCount = data.count
        let buffer: MTLBuffer? = data.withUnsafeBytes { pointer in
            guard let bytes = pointer.baseAddress?.assumingMemoryBound(to: type) else { return nil }
            let mutableRawPointer = UnsafeMutableRawPointer(mutating: bytes)
            return makeBuffer(bytesNoCopy: mutableRawPointer, length: byteCount, options: [.storageModeShared])
        }
        buffer?.label = label
        return buffer
    }


    /// Attempts to create a MTLBuffer by mmap'ing the specified local file url.
    /// - Parameters:
    ///   - url: The local file url that holds the bytes to create the MTLBuffer from.
    ///   - type: The underlying data type of the data block
    /// - Returns: A  new buffer that wraps an existing contiguous memory allocation.
    func makeBufferNoCopy<T>(_ url: URL, type: T.Type) -> MTLBuffer? {
        guard var bufferData = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        let byteCount = bufferData.count
        let buffer: MTLBuffer? = bufferData.withUnsafeMutableBytes { pointer in
            guard let bytes = pointer.baseAddress?.assumingMemoryBound(to: type) else { return nil }
            let mutableRawPointer = UnsafeMutableRawPointer(bytes)
            return makeBuffer(bytesNoCopy: mutableRawPointer, length: byteCount, options: [.storageModeShared])
        }
        buffer?.label = url.lastPathComponent
        return buffer
    }
}
