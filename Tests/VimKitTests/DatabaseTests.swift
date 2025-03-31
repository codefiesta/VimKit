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
class DatabaseTests {

    /// The vim file.
    private let vim: Vim = .init()

    /// Convenience var for accessing the database.
    private var db: Database {
        vim.db!
    }

    /// Convenience var for accessing the model context.
    private var modelContext: ModelContext {
        ModelContext(db.modelContainer)
    }

    private let urlString = "https://storage.cdn.vimaec.com/samples/residence.v1.2.75.vim"
    private var url: URL {
        .init(string: urlString)!
    }

    /// Initializer.
    init() async throws {
        await vim.load(from: url)
        await #expect(vim.state == .ready)
        try! await importDatabase()
    }

    /// Imports the vim database into SwiftData.
    private func importDatabase() async throws {
        #expect(db.tableNames.count > 0)

        let importer = Database.ImportActor(db)
        await importer.import()
        await #expect(importer.progress.isFinished == true)
    }

    @Test("Verify import state")
    func verifyImportState() async throws {

        // Verifies all meta data is all in an imported state
        let descriptor = FetchDescriptor<Database.ModelMetadata>(sortBy: [SortDescriptor(\.name)])
        let results = try! modelContext.fetch(descriptor)
        #expect(results.isNotEmpty)
        for result in results {
            #expect(result.state != .failed)
        }
    }

    @Test("Verify categories imported")
    func verifyCategories() async throws {

        // Only load system families
        let descriptor = FetchDescriptor<Database.Category>(sortBy: [SortDescriptor(\.index)])
        let results = try! modelContext.fetch(descriptor)
        #expect(results.isNotEmpty)
    }

    @Test("Verify families imported")
    func verifyFamilies() async throws {

        // Only load system families
        let predicate = #Predicate<Database.Family> { $0.isSystemFamily == true }

        let descriptor = FetchDescriptor<Database.Family>(predicate: predicate, sortBy: [SortDescriptor(\.index)])
        let results = try! modelContext.fetch(descriptor)
        #expect(results.isNotEmpty)
        for result in results {
            #expect(result.isSystemFamily == true)
        }
    }

    @Test("Verify levels imported")
    func verifyLevels() async throws {
        let descriptor = FetchDescriptor<Database.Level>(sortBy: [SortDescriptor(\.elevation)])
        let results = try! modelContext.fetch(descriptor)
        #expect(results.isNotEmpty)
        for result in results {
            #expect(result.element?.familyName == "Level")
            #expect(result.element?.category?.name == "Levels")
        }
    }
}
