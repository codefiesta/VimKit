//
//  SearchTests.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Foundation
import Testing
@testable import VimKit

@Suite("Search Tests",
       .tags(.utility))
class SearchTests {

    @Test("Verify Search")
    func verifySearch() async throws {
        let samples = [
            "Ceilings",
            "Compound Ceiling"
        ]

        let results = samples.search("Wood Slat Ceilings")!
        #expect(results.isNotEmpty)
        debugPrint("✅", results)
    }
}
