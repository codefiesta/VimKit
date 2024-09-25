//
//  UnsafeBufferPointer+Extensions.swift
//
//
//  Created by Kevin McKee
//

import Foundation

extension UnsafeBufferPointer {

    /// Splits the pointer values into chunks of n.
    /// - Parameter size: the size of chunks.
    /// - Returns: an array of pointer values split into chunks of the specified size.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
