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
            return descriptor.dataType.size * descriptor.arity
        }
    }
}

extension Array where Element == Geometry.Attribute {

    func makeBufferNoCopy<T>(device: MTLDevice, type: T.Type) -> MTLBuffer? {
        guard self.isNotEmpty else { return nil }
        if self.count > 1 {
            var buffer = data
            return device.makeBufferNoCopy(&buffer, type: type)
        } else {
            // Handle a single element array
            let attribute = self[0]
            var data = attribute.buffer.data
            return device.makeBufferNoCopy(&data, attribute.buffer.name, type: type)
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

