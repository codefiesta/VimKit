//
//  CGPoint+Extensions.swift
//  
//
//  Created by Kevin McKee
//

import CoreGraphics

public extension CGPoint {

    /// A convenience nan point used for comparison.
    static var nan: CGPoint {
        CGPoint(x: CGFloat.nan, y: CGFloat.nan)
    }

    /// Convenience operator that performs point multiplication.
    /// - Parameters:
    ///   - lhs: the point to multiply against
    ///   - rhs: the mulitplication factor
    /// - Returns: a new point that is multiplied by the right hand side value.
    static func * (lhs: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x * scale, y: lhs.y * scale)
    }

    /// Convenience operator that performs point multiplication.
    /// - Parameters:
    ///   - lhs: the point to divide against
    ///   - rhs: the divider
    /// - Returns: a new point that is divided by the right hand side value.
    static func / (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
        CGPoint(x: lhs.x / rhs, y: lhs.y / rhs)
    }

    /// Convenience initializer.
    init(x: Float, y: Float) {
        self.init(x: CGFloat(x), y: CGFloat(y))
    }

    /// Clamp the x,y to the range [`min`, max]. If x or y is
    /// NaN, the corresponding result is `min`.
    func clamp(min: CGPoint = .zero, max: CGPoint) -> CGPoint {
        guard self != .nan else { return min }
        var result: CGPoint = self
        result.x = CGFloat.minimum(CGFloat.maximum(result.x, min.x), max.x)
        result.y = CGFloat.minimum(CGFloat.maximum(result.y, min.y), max.y)
        return result
    }

    /// Clamp the x,y to the range [`min`, max]. If x or y is
    /// NaN, the corresponding result is `min`.
    func clamp(min: CGSize = .zero, max: CGSize) -> CGPoint {
        clamp(max: CGPoint(x: max.width, y: max.height))
    }
}
