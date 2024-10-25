//
//  NSCache+Extensions.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Foundation

/// Provides a Swift wrapper around NSCache.
final class Cache<Key: Hashable, Value>: @unchecked Sendable {

    /// Holds a set of cache keys.
    var keys: Set<Key> = .init()
    /// The backing storage of this cache.
    private let storage = NSCache<WrappedKey, Entry>()
    /// The lock mechanism.
    private let lock = NSLock()

    /// The maximum number of objects the cache should hold.
    var countLimit: Int {
        get {
            storage.countLimit
        }
        set {
            storage.countLimit = newValue
        }
    }

    /// The maximum total cost that the cache can hold before it starts evicting objects.
    var totalCostLimit: Int {
        get {
            storage.totalCostLimit
        }
        set {
            storage.totalCostLimit = newValue
        }
    }

    /// Whether the cache will automatically evict discardable-content objects whose content has been discarded.
    var evictsObjectsWithDiscardedContent: Bool {
        get {
            storage.evictsObjectsWithDiscardedContent
        }
        set {
            storage.evictsObjectsWithDiscardedContent = newValue
        }
    }

    /// Sets the value of the specified key in the cache.
    /// - Parameters:
    ///   - value: the value
    ///   - key: the key
    func insert(_ value: Value, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        let entry = Entry(value: value)
        storage.setObject(entry, forKey: WrappedKey(key))
        keys.insert(key)
    }

    /// Returns the value associated with a given key.
    /// - Parameter key: the key
    /// - Returns: the value associated with the given key
    func value(for key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return storage.object(forKey: WrappedKey(key))?.value
    }

    /// Removes the value of the specified key in the cache.
    /// - Parameter key: the key to remove
    func removeValue(for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeObject(forKey: WrappedKey(key))
        keys.remove(key)
    }

    /// Empties the cache.
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAllObjects()
        keys.removeAll()
    }

    /// Convenience subscript to retrive or set the value for the  given key.
    /// - Parameter key: the value key
    subscript(key: Key) -> Value? {
        get {
            value(for: key)
        }
        set {
            guard let value = newValue else {
                // Remove the value if nil as assigned
                removeValue(for: key)
                return
            }
            insert(value, for: key)
        }
    }
}

private extension Cache {

    /// The key wrapper that allows us to wrap any hashable key as `AnyObject` for NSCache conformance.
    final class WrappedKey: NSObject {

        let key: Key

        override var hash: Int {
            key.hashValue
        }

        init(_ key: Key) {
            self.key = key
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let value = object as? WrappedKey else { return false }
            return value.key == key
        }
    }
}

private extension Cache {

    /// The cache entry wrapper that allows us the value as `AnyObject` for NSCache conformance.
    final class Entry {

        let value: Value

        init(value: Value) {
            self.value = value
        }
    }
}
