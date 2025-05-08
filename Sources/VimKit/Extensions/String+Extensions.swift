//
//  String+Extensions.swift
//  
//
//  Created by Kevin McKee
//

import CryptoKit
import Foundation

public extension String {

    /// Denotes an empty string.
    static let empty = ""

    /// Calculates the SHA hash of this string instance
    var sha256Hash: String {
        let hashed = SHA256.hash(data: Data(self.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Convenience var that trim all whitespace.
    var trimmed: String {
        trimmingCharacters(in: .whitespaces)
    }

    /// Convenience subscript using a countable closed range.
    /// - Parameters:
    ///   - bounds: the bounds to subscript
    /// - Returns: a string at the specified bounds
    subscript (bounds: CountableClosedRange<Int>) -> String {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return String(self[start...end])
    }

    /// Convenience subscript using a countable range.
    /// - Parameters:
    ///   - bounds: the bounds to subscript
    /// - Returns: a string at the specified bounds
    subscript (bounds: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: bounds.lowerBound)
        let end = index(startIndex, offsetBy: bounds.upperBound)
        return String(self[start..<end])
    }
}
