//
//  Array+Extensions.swift
//  
//
//  Created by Kevin McKee
//

import Foundation

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
