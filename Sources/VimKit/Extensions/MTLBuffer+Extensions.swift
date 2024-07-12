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

    /// Builds an UnsafeMutableBufferPointer from the buffer contents.
    /// - Parameter count: the count of elements inside the buffer
    /// - Returns: a mutable buffer pointer of the specified type and
    func toUnsafeMutableBufferPointer<T>(_ count: Int) -> UnsafeMutableBufferPointer<T> {
        let pointer: UnsafeMutablePointer<T> = contents().assumingMemoryBound(to: T.self)
        let bufferPointer = UnsafeMutableBufferPointer(start: pointer, count: count)
        return bufferPointer
    }
}
