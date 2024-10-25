//
//  Database+Importer.swift
//  
//
//  Created by Kevin McKee
//

import Combine
import Foundation
import SwiftData

private typealias CacheKey = String
private let cacheTotalCostLimit = 1024 * 1024 * 8 * 8
private let batchSize = 100000

extension Database {

    /// Cancels all running tasks.
    public func cancel() {
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()

        // This is a very misleading method name, as this method simply
        // disconnects the model container from it's underlying data store
        modelContainer.deleteAllData()
    }

    /// Starts the import process.
    /// - Parameters:
    ///   - limit: the max limit of models per entity to import
    public func `import`(limit: Int = .max) async {

        // Check if the import should
        let checkTask = Task { @MainActor in
            switch state {
            case .importing, .ready, .error(_):
                return false
            case .unknown:
                // Check the tracker
                if let _ = ImportTaskTracker.shared.tasks[sha256Hash] {
                    debugPrint("💩 Task already running")
                    publish(state: .importing)
                    return false
                }
                return true
            }
        }

        let shouldImport = await checkTask.value

        if shouldImport {
            ImportTaskTracker.shared.tasks[sha256Hash] = true
            let importer = Database.ImportActor(self)
            await importer.import(limit)
        }
    }

    /// A thread safe actor type that handles the importing
    /// of vim database information into a SwiftData container.
    actor ImportActor: ModelActor, ObservableObject {

        /// Progress reporting importing model data into the container.
        @MainActor @Published
        var progress = Progress(totalUnitCount: Int64(Database.models.count))

        let database: Database
        let modelContainer: ModelContainer
        let modelExecutor: ModelExecutor
        let cache: ImportCache
        var count = 0

        /// Determines if the context shouid perform a save operation.
        var shouldSave: Bool {
            modelContext.insertedModelsArray.count >= batchSize ||
            modelContext.changedModelsArray.count >= batchSize
        }

        /// Initializer
        /// - Parameters:
        ///   - database: the vim database
        init(_ database: Database) {
            self.database = database
            self.modelContainer = database.modelContainer
            let modelContext = ModelContext(modelContainer)
            self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
            self.cache = ImportCache(modelContext)
        }

        /// Starts the import process.
        /// - Parameter limit: the max limit of models per entity to import
        func `import`(_ limit: Int = .max) {
            defer {
                // Remove the task from the tracker
                ImportTaskTracker.shared.tasks.removeValue(forKey: database.sha256Hash)
                do {
                    try modelContext.save()
                    database.publish(state: .ready)
                } catch (let error) {
                    database.publish(state: .error(error.localizedDescription))
                }
            }

            let start = Date.now

            // Warm the cache for the models. TODO: This could be reworked ...
            for modelType in Database.models {
                let modelName = modelType.modelName
                guard shouldImport(modelName) else {
                    debugPrint("􁃎 [\(modelName)] - skipping cache warming")
                    continue
                }
                warmCache(modelType, limit)
            }

            // Perform a batch insert of all of the cached models
            cache.batchInsert()

            for modelType in Database.models {

                // Update the progress whether we skip import or not
                defer {
                    if shouldSave {
                        try? modelContext.save()
                    }
                    Task { @MainActor in
                        progress.completedUnitCount += 1
                    }
                }

                let modelName = modelType.modelName
                guard shouldImport(modelName) else {
                    debugPrint("􁃎 [\(modelName)] - skipping import")
                    continue
                }

                importModel(modelType, limit)
            }
            let timeInterval = abs(start.timeIntervalSinceNow)
            debugPrint("􁗫 Database imported [\(count)] models in [\(timeInterval.stringFromTimeInterval())]")
            cache.empty()
        }

        /// Warms the cache for the specified model type.
        /// - Parameters:
        ///   - modelType: the type of model
        ///   - limit: the cache size limit
        private func warmCache(_ modelType: any IndexedPersistentModel.Type, _ limit: Int) {
            guard let table = database.tables[modelType.modelName] else { return }
            let count = min(table.rows.count, limit)
            _ = modelType.warm(size: count, cache: cache)
        }

        /// Imports models of the specified type into the model container.
        /// - Parameters:
        ///   - modelType: the model type
        ///   - limit: the max limit of models to import
        private func importModel(_ modelType: any IndexedPersistentModel.Type, _ limit: Int) {
            let modelName = modelType.modelName
            guard let table = database.tables[modelName] else {
                updateMeta(modelName, state: .failed)
                return
            }

            let start = Date.now
            let rowCount = table.rows.count
            debugPrint("􀈄 [\(modelType.modelName)] - importing [\(rowCount)] models")
            for i in 0..<rowCount {
                if i >= limit || Task.isCancelled { break }

                let index = Int64(i)
                let row = table.rows[i]
                upsert(index: index, modelType, data: row)
                count += 1
            }
            let timeInterval = abs(start.timeIntervalSinceNow)
            let state: ModelMetadata.State = Task.isCancelled ? .failed : .imported
            debugPrint("􂂼 [\(modelName)] - [\(state)] [\(rowCount)] in [\(timeInterval.stringFromTimeInterval())]")
            updateMeta(modelName, state: state)
        }

        /// Determines if we should import the model with the specified name of skip it.
        /// - Parameter modelName: the name of the model
        /// - Returns: true if the import should happen, otherwise false.
        private func shouldImport(_ modelName: String) -> Bool {
            let meta = meta(modelName)
            switch meta.state {
            case .importing, .imported:
                return false
            case .unknown, .failed:
                return true
            }
        }

        /// Returns the model meta data for the specified model name.
        /// - Parameter modelName: the name of the model
        /// - Returns: the model meta data
        private func meta(_ modelName: String) -> ModelMetadata {
            let predicate = #Predicate<ModelMetadata>{ $0.name == modelName }
            var fetchDescriptor = FetchDescriptor<ModelMetadata>(predicate: predicate)
            fetchDescriptor.fetchLimit = 1
            guard let results = try? modelContext.fetch(fetchDescriptor), results.isNotEmpty else {
                // No record so insert one
                let meta = ModelMetadata()
                meta.name = modelName
                meta.state = .unknown
                modelContext.insert(meta)
                return meta
            }
            return results[0]
        }

        /// Updates the model meta state
        /// - Parameters:
        ///   - modelName: the name of the model
        ///   - state: the state
        private func updateMeta(_ modelName: String, state: ModelMetadata.State) {
            let meta = meta(modelName)
            meta.state = state
        }

        /// Upserts a model of the specified type at the specified index with the row data.
        /// - Parameters:
        ///   - index: the index of the model
        ///   - modelType: the model type
        ///   - row: the model row data
        private func upsert(index: Int64, _ modelType: any IndexedPersistentModel.Type, data: [String: AnyHashable]) {
            guard !Task.isCancelled else { return }
            let model = modelType.findOrCreate(index: index, cache: cache)
            model.update(from: data, cache: cache)
        }

        /// Finds or creates a model with the specified index and type.
        /// - Parameter index: the model index
        /// - Returns: a found model of the specified type and index or a new instance.
        func findOrCreate<T>(_ index: Int64) -> T where T: IndexedPersistentModel {
            cache.findOrCreate(index)
        }
    }

    public final class ImportCache {

        let modelContext: ModelContext
        private var caches = [CacheKey: ModelCache]()

        /// Initializer.
        /// - Parameter modelContext: the model context to use
        init(_ modelContext: ModelContext) {
            self.modelContext = modelContext
        }

        /// Warms the cache to a specific size
        /// - Parameter size: the size of the cache
        /// - Returns: a list of models that have been cached.
        @discardableResult
        func warm<T>(_ size: Int) -> [T] where T: IndexedPersistentModel {
            let cacheKey: CacheKey = T.modelName
            let cache = findOrCreateCache(cacheKey)
            return cache.warm(size)
        }

        /// Performs a batch insert of cached models. This is a performance optimization
        /// that wraps all model context inserts into a single transaction and performs a single save to
        /// avoid the overhead of writing to disk.
        func batchInsert() {
            debugPrint("􀈄 [Batch] inserting models from cache.")

            let start = Date.now
            var batchCount = 0

            defer {
                let timeInterval = abs(start.timeIntervalSinceNow)
                debugPrint("􂂼 [Batch] inserted [\(batchCount)] models in [\(timeInterval.stringFromTimeInterval())]")

            }

            try? modelContext.transaction {
                for (_, cache) in caches {
                    for key in cache.keys {
                        guard let model = cache[key] else { continue }
                        modelContext.insert(model)
                        batchCount += 1
                    }
                }
                try? modelContext.save()
            }
        }

        /// Finds or creates a model with the specified index and type.
        /// - Parameter index: the model index
        /// - Returns: a found model of the specified type and index or a new instance.
        func findOrCreate<T>(_ index: Int64) -> T where T: IndexedPersistentModel {
            let cacheKey: CacheKey = T.modelName
            let cache = findOrCreateCache(cacheKey)
            return cache.findOrCreate(index)
        }

        /// Finds or creates a cache with the specified cacheKey
        /// - Parameter cacheKey: the cache key to use
        /// - Returns: a model cache with the specified key
        private func findOrCreateCache(_ cacheKey: CacheKey) -> ModelCache {
            guard let cache = caches[cacheKey] else {
                let cache = ModelCache(modelContext)
                caches[cacheKey] = cache
                return cache
            }
            return cache
        }

        /// Empties all of the caches.
        func empty() {
            for (_, cache) in caches {
                cache.empty()
            }
        }
    }

    fileprivate final class ModelCache {

        let modelContext: ModelContext

        private lazy var cache: Cache<Int64, any IndexedPersistentModel> = {
            let cache = Cache<Int64, any IndexedPersistentModel>()
            cache.totalCostLimit = cacheTotalCostLimit
            cache.evictsObjectsWithDiscardedContent = true
            return cache
        }()

        /// Convenience var for accessing the cache keys.
        var keys: Set<Int64> {
            cache.keys
        }

        /// Initializer.
        /// - Parameter modelContext: the model context to use
        init(_ modelContext: ModelContext) {
            self.modelContext = modelContext
        }

        /// Warms the cache up to the specified index size. Any entities that
        /// have cache index misses are stubbed out skeletons that can later be filled in with `.update(data:cache:)`.
        /// Please note that he models that are inserted into the cache are not inserted into the model context. As an import optimization,
        /// all of the models are are inserted via the `.batchInsert()` method.
        /// - Parameter size: the upper bounds of the model index size
        /// - Returns: empty results for now, simply used to infer type from the generic - could be reworked
        @discardableResult
        func warm<T>(_ size: Int) -> [T] where T: IndexedPersistentModel {
            let cacheKey: CacheKey = T.modelName
            if size <= .zero {
                debugPrint("􂂼 [\(cacheKey)] - skipping warm - [\(models.count)] [\(size)]")
                return []
            }
            debugPrint("􁰹 [\(cacheKey)] - warming cache [\(size)]")

            let start = Date.now

            let results = T.fetch(in: modelContext)
            results.forEach { model in
                cache[model.index] = model
            }

            if results.count == size {
                let timeInterval = abs(start.timeIntervalSinceNow)
                debugPrint("􂂼 [\(cacheKey)] - cache created [\(size)] in [\(timeInterval.stringFromTimeInterval())]")
                return []
            }

            let range: Range<Int64> = 0..<Int64(size)
            let indexes = Set(range)
            let cacheHits = Set(results.map{ $0.index })
            let cacheMisses = indexes.subtracting(cacheHits)
            for index in cacheMisses {
                let model: T = .init()
                model.index = index
                assert(model.index != .empty)
                cache[index] = model
            }
            let timeInterval = abs(start.timeIntervalSinceNow)
            debugPrint("􂂼 [\(cacheKey)] - cache created [\(size)] with [\(cacheMisses.count)] misses in [\(timeInterval.stringFromTimeInterval())]")
            return []
        }

        /// Finds or creates an indexed entity with the specified index.
        /// - Parameter index: the entity index.
        /// - Returns: an entity with the specified index.
        func findOrCreate<T>(_ index: Int64) -> T where T: IndexedPersistentModel {
            guard let model = cache[index] as? T else {
                let predicate = T.predicate(index)
                var fetchDescriptor = FetchDescriptor<T>(predicate: predicate)
                fetchDescriptor.fetchLimit = 1
                guard let results = try? modelContext.fetch(fetchDescriptor), results.isNotEmpty else {
                    let model: T = .init()
                    model.index = index
                    modelContext.insert(model)
                    assert(model.index != .empty)
                    cache[index] = model
                    return model
                }
                let result = results[0]
                cache[index] = result
                return result
            }
            return model
        }

        /// Convenience subscript to retrive the cache value for the given key.
        /// - Parameter key: the value key
        subscript(key: Int64) -> (any IndexedPersistentModel)? {
            cache[key]
        }

        /// Empties the cache entries.
        func empty() {
            cache.removeAll()
        }
    }
}

/// A singleton that keeps track of current import tasks.
fileprivate class ImportTaskTracker: @unchecked Sendable {

    static let shared = ImportTaskTracker()

    /// Import tasks.
    var tasks = [String: Bool]()
}
