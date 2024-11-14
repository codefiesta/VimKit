//
//  MTLSize+Extensions.swift
//  VimKit
//
//  Created by Kevin McKee
//

import MetalKit

extension MTLSize {

    /// Constant that holds a size of zero in all lanes.
    static var zero: MTLSize {
        .init(width: .zero, height: .zero, depth: .zero)
    }

    /// Divides this size by the denominator and rounds up.
    /// - Parameter denominator: the size denominator
    /// - Returns: the new size divded by the denominator and rounded up
    func divideRoundUp(_ denominator: MTLSize) -> MTLSize {
        let w = (width + denominator.width - 1) / denominator.width
        let h = (height + denominator.height - 1) / denominator.height
        let d = (depth + denominator.depth - 1) / denominator.depth
        return .init(width: w, height: h, depth: d)
    }

    /// Convenience operator that performs equality checks.
    /// - Parameters:
    ///   - lhs: the left size to check
    ///   - rhs: the right size to check
    /// - Returns: true if the sizes are equal
    public static func == (lhs: MTLSize, rhs: MTLSize) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.depth == rhs.depth
    }

    /// Convenience operator that performs non-equality checks.
    /// - Parameters:
    ///   - lhs: the left size to check
    ///   - rhs: the right size to check
    /// - Returns: true if the size are not equal
    public static func != (lhs: MTLSize, rhs: MTLSize) -> Bool {
        lhs.width != rhs.width || lhs.height != rhs.height || lhs.depth != rhs.depth
    }
}
