//
//  NSCache+Extensions.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Foundation


/// Provides a Swift wrapper around NSCache.
final class Cache<Key: Hashable, Value> {

    private let wrapped = NSCache<WrappedKey, Entry>()
    private let lock = NSLock()

    var countLimit: Int {
        get {
            wrapped.countLimit
        }
        set {
            wrapped.countLimit = newValue
        }
    }

    var totalCostLimit: Int {
        get {
            wrapped.totalCostLimit
        }
        set {
            wrapped.totalCostLimit = newValue
        }
    }

    func insert(_ value: Value, for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        let entry = Entry(value: value)
        wrapped.setObject(entry, forKey: WrappedKey(key))
    }

    func value(for key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return wrapped.object(forKey: WrappedKey(key))?.value
    }

    func removeValue(for key: Key) {
        lock.lock()
        defer { lock.unlock() }
        wrapped.removeObject(forKey: WrappedKey(key))
    }

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

    final class Entry {

        let value: Value

        init(value: Value) {
            self.value = value
        }
    }
}
