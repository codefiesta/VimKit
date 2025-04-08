//
//  Range+Extensions.swift
//  VimKit
//
//  Created by Kevin McKee
//

public extension Range {

    /// Custom contains operator that checks if the range contains any elements inside the array.
    /// - Parameters:
    ///   - lhs: the range to check
    ///   - rhs: the array to check
    /// - Returns: true if the range contains any of the elements inside the given array.
    static func ~= (lhs: Range<Bound>, rhs: [Bound]) -> Bool {
        for element in rhs {
            if lhs.contains(element){
                return true
            }
        }
        return false
    }
}

