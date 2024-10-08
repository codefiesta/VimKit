//
//  BoundedRange+Extensions.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Foundation
import VimKitShaders

extension BoundedRange: @retroactive Equatable, @retroactive Hashable {

    var count: Int {
        Int(upperBound) - Int(lowerBound)
    }

    /// Convenience var to convert the bounded range into a Swift range.
    var range: Range<Int> {
        Int(lowerBound)..<Int(upperBound)
    }

    init(_ range: Range<Int>) {
        self.init(lowerBound: UInt32(range.lowerBound), upperBound: UInt32(range.upperBound))
    }

    public static func == (lhs: BoundedRange, rhs: BoundedRange) -> Bool {
        lhs.lowerBound == rhs.lowerBound && lhs.upperBound == rhs.upperBound
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(lowerBound)
        hasher.combine(upperBound)
    }
}

extension Array {

    // Convenience subscript using a bounded range
    subscript(boundedRange: BoundedRange) -> ArraySlice<Element> {
        let range = Int(boundedRange.lowerBound)..<Int(boundedRange.upperBound)
        return self[range]
    }

    // Convenience subscript using an UInt32 index
    subscript(index: UInt32) -> Element {
        self[Int(index)]
    }

    // Convenience subscript using an Int32 index
    subscript(index: Int32) -> Element {
        assert(index != .empty, "Attempt to subscript with an negative index")
        return self[Int(index)]
    }
}

extension UnsafeMutableBufferPointer {

    // Convenience subscript using a bounded range
    subscript(boundedRange: BoundedRange) -> Slice<UnsafeMutableBufferPointer<Element>> {
        let range = Int(boundedRange.lowerBound)..<Int(boundedRange.upperBound)
        return self[range]
    }

    // Convenience subscript using an Int32 index
    subscript(index: Int32) -> Element {
        self[Int(index)]
    }
}
