//
//  UnsafeMutableBufferPointer+Extensions.swift
//
//
//  Created by Kevin McKee
//

import Foundation

extension UnsafeMutableBufferPointer {

    /// Splits the pointer values into chunks of n.
    /// - Parameter size: the size of the chunks
    /// - Returns: the pointer contiguous values split into chunks on n
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
