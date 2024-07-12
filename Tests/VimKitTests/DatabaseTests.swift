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
        let url = Bundle.module.url(forResource: "sample", withExtension: "vim")!
        let vim = Vim(url)

        // Subscribe to the file state
        let readyExpection = self.expectation(description: "Ready")
        vim.$state.sink { state in
            switch state {
            case .initializing:
                break
            case .downloading:
                break
            case .loading:
                break
            case .ready:
                // The file is now ready to be read
                readyExpection.fulfill()
            case .error:
                break
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

        let importer = Database.ImportActor(db, modelContainer: modelContainer)
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

        // Check the camera
        let cameraDescriptor = FetchDescriptor<Database.Camera>()
        let cameraCount = try! modelContext.fetchCount(cameraDescriptor)
        XCTAssertTrue(cameraCount > 0, "Cameras are empty!")

        // Check the viewpoint
        let viewDescriptor = FetchDescriptor<Database.View>()
        let views = try! modelContext.fetch(viewDescriptor)
        XCTAssertTrue(views.isNotEmpty, "Views are empty!")
        let view = views[0]
        XCTAssertNotEqual(view.position, .zero)
        XCTAssertNotEqual(view.direction, .zero)
        XCTAssertNotEqual(view.origin, .zero)
        XCTAssertNotNil(view.camera, "View camera is nil!")
        XCTAssertNotNil(view.element, "View element is nil!")

        // Parameters
        let parameterFetchDescriptor = FetchDescriptor<Database.Parameter>(sortBy: [SortDescriptor(\.index)])
        let parameterCount = try! modelContext.fetchCount(parameterFetchDescriptor)
        XCTAssertTrue(parameterCount > 0, "Parameters are empty!")

        // Elements
        let elementPredicate = #Predicate<Database.Element> { $0.index != -1 && $0.parameters.count > 0 }
        let elementFetchDescriptor = FetchDescriptor<Database.Element>(predicate: elementPredicate, sortBy: [SortDescriptor(\.index)])
        let elementCount = try! modelContext.fetchCount(elementFetchDescriptor)
        XCTAssertTrue(elementCount > 0, "Elements are empty!")

        // Worksets
        let worksetFetchDescriptor = FetchDescriptor<Database.Workset>(sortBy: [SortDescriptor(\.index)])
        let worksetsCount = try! modelContext.fetchCount(worksetFetchDescriptor)
        XCTAssertTrue(worksetsCount > 0, "Worksets are empty!")

        // Families + Categories
        let familyPredicate = #Predicate<Database.Family> { $0.category != nil && $0.category?.name != "" }
        let familyDescriptor = FetchDescriptor<Database.Family>(predicate: familyPredicate)
        let families = try! modelContext.fetch(familyDescriptor)
        XCTAssertTrue(families.isNotEmpty, "Families are empty!")

        let categories = families.compactMap{ $0.category }.uniqued().sorted{ $0.name < $1.name }
        XCTAssertTrue(categories.isNotEmpty, "Family Categories are empty!")
    }
}

