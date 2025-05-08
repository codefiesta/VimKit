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
}
