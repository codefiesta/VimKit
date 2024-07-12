//
//  UnsafeBufferPointer+Extensions.swift
//
//
//  Created by Kevin McKee
//

import Foundation

extension UnsafeBufferPointer {

    /// Splits the pointer values into chunks of n
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
