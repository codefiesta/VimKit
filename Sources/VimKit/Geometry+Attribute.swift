//
//  Geometry+Attribute.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Foundation
import MetalKit

extension Geometry {

    /// Provides a container of geometry data is described through it's attribute descriptor.
    /// See: https://github.com/vimaec/vim#vim-geometry-attributes
    public struct Attribute {

        let descriptor: AttributeDescriptor
        let buffer: BFast.Buffer

        // Returns the number elememts inside this attribute's data buffer
        var count: Int {
            descriptor.dataType.size * descriptor.arity
        }
    }
}

extension Array where Element == Geometry.Attribute {

    /// Helper method that creates a MTLBuffer from the array data.
    /// - Parameters:
    ///   - device: the metal device
    ///   - type: the data type
    /// - Returns: a new MTLBuffer that is either made from copy or no-copy depending on the data size and count.
    func makeBuffer<T>(device: MTLDevice, type: T.Type) -> MTLBuffer? {
        guard self.isNotEmpty else { return nil }
        var buffer = data
        if self.count > 1 {
            // If we have a combined data block, we'll need to copy the bytes :(
            return device.makeBuffer(data, type: type)
        }

        if buffer.count >= Data.minMmapByteSize {
            // Make the buffer without copying the bytes
            return device.makeBufferNoCopy(&buffer, type: type)
        } else {
            // Simply build a buffer by copying the bytes
            return device.makeBuffer(data, type: type)
        }
    }

    /// Helper method that converts an array of attributes to data,
    /// - Returns: the attribute data
    var data: Data {
        guard count > .zero else { return .init() }
        var data = self[0].buffer.data
        for i in 1..<count {
            data.append(self[i].buffer.data)
        }
        return data
    }
}

