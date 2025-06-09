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
private let cacheTotalCostLimit = 1024 * 1024 * 64
private let batchSize = 10000

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
            await importer.import()
        }
    }

    /// A thread safe actor type that handles the importing
    /// of vim database information into a SwiftData container.
    ///
    /// For discussion, see this thread as wrapping the context as an unchecked sendable across tasks.
    /// See: https://forums.developer.apple.com/forums/thread/736226
    actor ImportActor: ModelActor, ObservableObject {

        /// Progress reporting importing model data into the container.
        @MainActor @Published
        var progress = Progress(totalUnitCount: Int64(Database.models.count))

        private var subscribers = Set<AnyCancellable>()
        nonisolated let modelContainer: ModelContainer
        nonisolated let modelExecutor: ModelExecutor
        let database: Database
        let cache: ImportCache
        var count = 0

        /// Initializer
        /// - Parameters:
        ///   - database: the vim database
        init(_ database: Database) {
            self.database = database
            self.modelContainer = database.modelContainer
            self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
            self.cache = ImportCache()
            // Register subscribers
            NotificationCenter.default.publisher(for: ModelContext.willSave).sink { notification in
                guard let modelContext = notification.object as? ModelContext else { return }
                let insertCount = modelContext.insertedModelsArray.count
                let changeCount = modelContext.changedModelsArray.count
                debugPrint("􁗫 Model context will save [\(insertCount)] inserts, [\(changeCount)] changes.")
            }.store(in: &subscribers)
            NotificationCenter.default.publisher(for: ModelContext.didSave).sink { _ in
                debugPrint("􁗫 Model context saved.")
            }.store(in: &subscribers)
        }

        /// Starts the import process.
        func `import`() {

            let group = DispatchGroup()
            let start = Date.now

            defer {
                didImport(start)
            }

            let models = Database.models

            // 1) Warm the model cache by stubbing out model skeletons.
            for modelType in models {
                group.enter()
                Task {
                    defer {
                        group.leave()
                    }

                    let modelName = modelType.modelName
                    guard shouldImport(modelName) else {
                        debugPrint("􁃎 [\(modelName)] - skipping cache warming")
                        return
                    }
                    warmCache(modelType)
                }
            }

            group.wait()

            // 2) Stitch together all of model relationships
            let sortedModels = models.sorted{ $0.importPriority.rawValue > $1.importPriority.rawValue }
            for modelType in sortedModels {

                group.enter()

                Task {
                    // Update the progress whether we skip import or not
                    defer {
                        group.leave()
                        Task { @MainActor in
                            progress.completedUnitCount += 1
                        }
                    }

                    let modelName = modelType.modelName
                    guard shouldImport(modelName) else {
                        debugPrint("􁃎 [\(modelName)] - skipping import")
                        return
                    }
                    importModel(modelType)
                }
            }

            group.wait()

            // 3) Perform a batch insert for all the models
            batchInsert()
        }

        /// Performs post import tasks.
        /// - Parameter start: the import start date / time.
        private func didImport(_ start: Date) {
            // Remove the task from the tracker
            ImportTaskTracker.shared.tasks.removeValue(forKey: database.sha256Hash)
            // Update the database state
            database.publish(state: .ready)

            let timeInterval = abs(start.timeIntervalSinceNow)
            debugPrint("􁗫 Database imported [\(count)] models in [\(timeInterval.stringFromTimeInterval())]")

            // Empty the cache and remove all subscribers
            cache.empty()
            subscribers.removeAll()
        }

        /// Warms the cache for the specified model type.
        /// - Parameters:
        ///   - modelType: the type of model
        private func warmCache(_ modelType: any IndexedPersistentModel.Type) {
            guard let table = database.tables[modelType.modelName] else { return }
            modelType.warm(table: table, cache: cache)
        }

        /// Imports models of the specified type into the model container.
        /// - Parameters:
        ///   - modelType: the model type
        private func importModel(_ modelType: any IndexedPersistentModel.Type) {
            let modelName = modelType.modelName
            guard let table = database.tables[modelName] else { return }
            guard let modelCache = cache.caches[modelName] else { return }

            let keys = modelCache.keys
            let start = Date.now
            let rowCount = modelCache.keys.count//table.rows.count
            var state: ModelMetadata.State = .unknown

            defer {
                let timeInterval = abs(start.timeIntervalSinceNow)
                debugPrint("􂂼 [\(modelName)] - [\(state)] [\(rowCount)] in [\(timeInterval.stringFromTimeInterval())]")
                updateMeta(modelName, state: state)
            }

            debugPrint("􀈄 [\(modelName)] - importing [\(rowCount)] models")

            for index in keys {
                if Task.isCancelled { break }
                let row = table.rows[Int(index)]
                update(index: index, modelType, data: row)
                count += 1
            }
            state = Task.isCancelled ? .failed : .imported
        }

        /// Performs a batch insert of cached models. This is a performance optimization
        /// that wraps all model context inserts into a single transaction and performs a single save to
        /// avoid the overhead of writing to disk.
        private func batchInsert() {
            debugPrint("􀈄 [Batch] - inserting [\(cache.count)] models from cache.")

            let start = Date.now
            var batchCount = 0

            let models = Database.models.sorted{ $0.importPriority.rawValue > $1.importPriority.rawValue }
            let cacheKeys = models.map{ $0.modelName }

            defer {
                let timeInterval = abs(start.timeIntervalSinceNow)
                debugPrint("􂂼 [Batch] - inserted [\(batchCount)] models in [\(timeInterval.stringFromTimeInterval())]")
            }
            try? modelContext.transaction {
                for cacheKey in cacheKeys {

                    guard let modelCache = cache.caches[cacheKey] else { continue }
                    let start = Date.now
                    let keys = modelCache.keys

                    defer {
                        let timeInterval = abs(start.timeIntervalSinceNow)
                        debugPrint("􂂼 [Batch] - inserted [\(cacheKey)] [\(keys.count)] in [\(timeInterval.stringFromTimeInterval())]")
                        modelCache.empty()
                    }

                    for key in keys {
                        guard let model = modelCache[key] else { continue }
                        modelContext.insert(model)
                        batchCount += 1
                        modelCache.removeValue(for: key)
                    }
                }
            }
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

        /// Updates a model of the specified type at the specified index with the row data.
        /// - Parameters:
        ///   - index: the index of the model
        ///   - modelType: the model type
        ///   - row: the model row data
        private func update(index: Int64, _ modelType: any IndexedPersistentModel.Type, data: [String: AnyHashable]) {
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

    /// A type that holds a cache of models that can be used to hold in-memory models.
    public final class ImportCache: @unchecked Sendable {

        /// A hash of caches using the model name as the key and it's corresponding cache as the value.
        fileprivate var caches = [CacheKey: ModelCache]()

        /// Returns the total count of all models residing in all of the caches.
        var count: Int {
            caches.values.reduce(0) { $0 + $1.keys.count }
        }

        /// Initializer.
        init() {}

        /// Warms the cache to a specific size
        /// - Parameter table: the database table data
        /// - Returns: a list of models that have been cached.
        @discardableResult
        func warm<T>(_ table: Database.Table) -> [T] where T: IndexedPersistentModel {
            let cacheKey: CacheKey = T.modelName
            let cache = findOrCreateCache(cacheKey)
            return cache.warm(table)
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
                let cache = ModelCache()
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

    /// A type that holds a cache of specific models.
    fileprivate final class ModelCache: @unchecked Sendable {

        /// The backing storage cache.
        fileprivate lazy var cache: Cache<Int64, any IndexedPersistentModel> = {
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
        init() { }

        /// Warms the cache for the specified table. The entities are stubbed out skeletons that can later be filled in with `.update(data:cache:)`.
        /// Please note that he models that are inserted into the cache are not inserted into the model context. As an import optimization,
        /// all of the models are are inserted via the `.batchInsert()` method.
        /// - Parameter table: the database table to cache from
        /// - Returns: empty results for now, simply used to infer type from the generic - could be reworked
        @discardableResult
        func warm<T>(_ table: Database.Table) -> [T] where T: IndexedPersistentModel {
            let cacheKey: CacheKey = T.modelName
            let size = table.rows.count
            if size <= .zero {
                debugPrint("􂂼 [\(cacheKey)] - skipping warm - [\(models.count)] [\(size)]")
                return []
            }
            debugPrint("􁰹 [\(cacheKey)] - warming cache [\(size)]")

            var count = 0
            let start = Date.now
            defer {
                let timeInterval = abs(start.timeIntervalSinceNow)
                debugPrint("􂂼 [\(cacheKey)] - cache created [\(count)] in [\(timeInterval.stringFromTimeInterval())]")
            }

            for i in 0..<size {
                let index = Int64(i)
                let model: T = .init()
                model.index = index
                cache[index] = model
                count += 1
            }
            return []
        }

        /// Finds or creates an indexed entity with the specified index.
        /// - Parameter index: the entity index.
        /// - Returns: an entity with the specified index.
        func findOrCreate<T>(_ index: Int64) -> T where T: IndexedPersistentModel {
            guard let model = cache[index] as? T else {
                let model: T = .init()
                model.index = index
                cache[index] = model
                return model
            }
            return model
        }

        /// Convenience subscript to retrive the cache value for the given key.
        /// - Parameter key: the value key
        subscript(key: Int64) -> (any IndexedPersistentModel)? {
            cache[key]
        }

        /// Removes the value for the specified key.
        /// - Parameter key: the cache key
        func removeValue(for key: Int64) {
            cache.removeValue(for: key)
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
