//
//  File.swift
//  
//
//  Created by Kevin McKee
//

import MetalKit

public extension MTLBuffer {

    /// Convenience var that returns the byte count formatted into a human readable string.
    var byteCountFormatted: String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useAll]
        bcf.countStyle = .file
        let string = bcf.string(fromByteCount: Int64(length))
        return string
    }

    /// Builds an UnsafeMutableBufferPointer from the buffer contents of the specifed type.
    /// - Returns: a mutable buffer pointer of the specified type and length.
    func toUnsafeMutableBufferPointer<T>() -> UnsafeMutableBufferPointer<T> {
        let count = length/MemoryLayout<T>.stride
        let pointer: UnsafeMutablePointer<T> = contents().assumingMemoryBound(to: T.self)
        let bufferPointer = UnsafeMutableBufferPointer(start: pointer, count: count)
        return bufferPointer
    }

    /// Returns the buffer contents as mutable pointer of the specified type.
    /// - Returns: a mutable pointer of the specified type and length.
    func toUnsafeMutablePointer<T>() -> UnsafeMutablePointer<T> {
        let count = length/MemoryLayout<T>.stride
        let pointer: UnsafeMutablePointer<T> = contents().bindMemory(to: T.self, capacity: count)
        return pointer
    }
}
