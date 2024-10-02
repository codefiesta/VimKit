//
//  Array+Extensions.swift
//  
//
//  Created by Kevin McKee
//

import Foundation
import MetalKit

extension Array {

    /// Splits the array into chunks of n.
    /// - Parameter size: the size of chunks.
    /// - Returns: an array of arrays chunked into the specified size.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }

    /// Splits the array down the middle into two arrays.
    func split() -> ([Element], [Element]) {
        let half = count / 2 + count % 2
        let head = self[0..<half]
        let tail = self[half..<count]
        return (Array(head), Array(tail))
    }
}

extension Array where Element: Numeric {

    /// Attempts to create a MTLBuffer from an array of any numeric types by copying the bytes.
    /// - Parameters:
    ///   - device: the metal device to use
    ///   - label: the buffer label
    /// - Returns: an MTLBuffer from the array of elements
    func makeBuffer(device: MTLDevice, _ label: String? = nil) -> MTLBuffer? {
        guard self.isNotEmpty else { return nil }
        let byteCount = MemoryLayout<Element>.size * count
        let capacity = Int(byteCount / MemoryLayout<Element>.size)
        let buffer: MTLBuffer? = withUnsafeBytes { pointer in
            guard let rawPointer = pointer.baseAddress?.bindMemory(to: Element.self, capacity: capacity) else { return nil }
            return device.makeBuffer(bytes: rawPointer, length: byteCount)
        }
        buffer?.label = label
        return buffer
    }
}

extension Array where Element == SIMD3<Float> {

    /// Attempts to create a MTLBuffer from an array of SIMD3<Float> elements.
    /// - Parameters:
    ///   - device: the metal device to use
    ///   - label: the buffer label
    /// - Returns: an MTLBuffer from the array of elements
    func makeBuffer(device: MTLDevice, _ label: String? = nil) -> MTLBuffer? {
        guard self.isNotEmpty else { return nil }
        let packed = self.map { [$0.x, $0.y, $0.z] }.flatMap { $0 } // Pack the floats
        return packed.makeBuffer(device: device)
    }
}


