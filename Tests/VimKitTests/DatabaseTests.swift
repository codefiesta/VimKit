//
//  DatabaseTests.swift
//  
//
//  Created by Kevin McKee
//

import Combine
import SwiftData
@testable import VimKit
import XCTest

final class DatabaseTests: XCTestCase {

    private var subscribers = Set<AnyCancellable>()

    override func setUp() {
        subscribers.removeAll()
    }

    override func tearDown() {
        for subscriber in subscribers {
            subscriber.cancel()
        }
    }

    /// Tests importing a database into SwiftData
    func testImporter() async throws {
        let urlString = "https://vim.azureedge.net/samples/residence.vim"
        let url = URL(string: urlString)!
        let vim = Vim(url)

        // Subscribe to the file state
        let readyExpection = self.expectation(description: "Ready")
        vim.$state.sink { state in
            switch state {
            case .unknown, .initializing, .downloading, .loading, .error:
                break
            case .ready:
                // The file is now ready to be read
                readyExpection.fulfill()
            }
        }.store(in: &subscribers)

        // Wait for the file to be downloaded and put into a ready state
        await fulfillment(of: [readyExpection], timeout: 10)

        let db = vim.db!
        XCTAssertGreaterThan(db.tableNames.count, 0)

        let schema = Schema(Database.allTypes)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let modelContainer = try! ModelContainer(for: schema, configurations: configuration)
        XCTAssertNotNil(modelContainer)

        let importer = Database.ImportActor(db)
        await importer.import(100)

        // TODO: I kinda hate this while loop, but need to figure out how to observe async published vars
        var isFinished = false
        while !isFinished {
            isFinished = await importer.progress.isFinished
        }

        // Create a new model context for reading
        let modelContext = ModelContext(modelContainer)

        // Make sure the meta data is all in an imported state
        let metaDataDescriptor = FetchDescriptor<Database.ModelMetadata>(sortBy: [SortDescriptor(\.name)])
        guard let results = try? modelContext.fetch(metaDataDescriptor) else { return }
        for result in results {
            XCTAssertEqual(result.state, .imported)
        }
    }
}

