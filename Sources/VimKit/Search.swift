//
//  Search.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Foundation

protocol Searchable {
    /// The value to search for
    var searchableString: String { get }
}

extension String: Searchable {

    var searchableString: String { self }
}

extension Array where Element: Searchable {

    /// Performs a fuzzy search using the [levenshtein distance](https://en.wikipedia.org/wiki/Levenshtein_distance) algorithm.
    /// - Parameter searchString: the string to search for
    /// - Returns: an array of matching elements
    func search(_ searchString: String) -> [(item: Element, score: Double)]? {
        FuzzySearchLevenstein.fuzzySearch(searchString: searchString, candidates: self)
    }
}

/// ⭐️ Credit for this algorithm goes to [Writing a Generic Fuzzy Search Algorithm in Swift](https://github.com/tom-ludwig/FuzzySearch-with-SwiftUI)
struct FuzzySearchLevenstein {

    /// Calculates the [levenshtein distance](https://en.wikipedia.org/wiki/Levenshtein_distance)
    /// between the source and target sequences.
    /// - Parameters:
    ///   - source: the source sequence
    ///   - target: the target sequence
    /// - Returns: the levenshtein distance
    static func levenshteinDistanceVector(source: [UInt16], target: [UInt16]) -> UInt16 {
        let sourceLength = source.count
        let targetLength = target.count
        var distances = [UInt16](repeating: 0, count: targetLength + 1)

        // Initialise the first row
        for columnIndex in 0...targetLength {
            distances[columnIndex] = UInt16(columnIndex)
        }

        for rowIndex in 1...sourceLength {
            var previousDistance = distances[0]
            distances[0] = UInt16(rowIndex)

            for columnIndex in 1...targetLength {
                let substitutionCost = source[rowIndex - 1] != target[columnIndex - 1]
                let oldDistance = distances[columnIndex]

                distances[columnIndex] = min(
                    distances[columnIndex] + 1, // Insert into target
                    previousDistance + (substitutionCost ? 1 : 0), // Substitute
                    distances[columnIndex - 1] + 1 // Delete from target
                )
                previousDistance = oldDistance
            }
        }
        return distances[targetLength]
    }

    /// Performs a fuzzy search using the levenshtein distance algorithm.
    /// - Parameters:
    ///   - searchString: the search query string
    ///   - candidates: the search candidates
    ///   - threshold: the minimun threshold that a score must
    /// - Returns: an ordered list of
    static func fuzzySearch<T>(searchString: String, candidates: [T], threshold: Double = .zero) -> [(item: T, score: Double)]? where T: Searchable {
        guard !searchString.isEmpty else { return nil }

        let targetVector = searchString.unicodeScalars.map { scalar in UInt16(scalar.value) }
        let targetStringLength = searchString.count

        let results: [(item: T, score: Double)] = candidates.map { candidate in
            let candidateString = candidate.searchableString
            let candidateVector = candidateString.unicodeScalars.map { scalar in UInt16(scalar.value) }

            let distance = levenshteinDistanceVector(source: candidateVector, target: targetVector)
            let score = 1.0 - Double(distance) / max(Double(targetStringLength), Double(candidateString.count))

            return (item: candidate, score: score)
        }

        return results.filter { $0.score > threshold }
            .sorted { $0.score > $1.score }
    }
}
