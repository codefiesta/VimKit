//
//  DatabaseTests.swift
//  
//
//  Created by Kevin McKee
//

import Foundation
import SwiftData
import Testing
@testable import VimKit

/// Skip tests that require downloads on Github runners.
private let testsEnabled = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] == nil

@Suite("Database Tests",
       .enabled(if: testsEnabled),
       .tags(.database))
struct DatabaseTests {

    private let vim: Vim = .init()
    private let urlString = "https://storage.cdn.vimaec.com/samples/residence.v1.2.75.vim"
    private var url: URL {
        .init(string: urlString)!
    }

    @Test("Importing database into SwiftData")
    func whenImporting() async throws {
        await vim.load(from: url)
        await #expect(vim.state == .ready)

        let db = vim.db!
        #expect(db.tableNames.count > 0)

        let importer = Database.ImportActor(db)
        await importer.import()

        // Create a new model context for reading
        let modelContext = ModelContext(db.modelContainer)

        // Make sure the meta data is all in an imported state
        let metaDataDescriptor = FetchDescriptor<Database.ModelMetadata>(sortBy: [SortDescriptor(\.name)])
        guard let results = try? modelContext.fetch(metaDataDescriptor) else { return }
        for result in results {
            #expect(result.state != .failed)
        }
    }
}
