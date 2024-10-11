//
//  Assets+Cache.swift
//  VimKit
//
//  Created by Kevin McKee
//

import SwiftUI
import VimKit

#if os(macOS)
private typealias CacheType = NSImage
#else
private typealias CacheType = UIImage
#endif

// The maximum number of objects the cache should hold.
private let countLimit = 100

extension Assets {

    /// Fetches the asset with the give name as an image.
    func image(_ name: String) -> Image? {

        // 1) Try to fetch the image straight out of the cache
        if let image = ImageCache.shared.image(for: name) {
            return .init(cacheType: image)
        }

        // 2) Try and load the image straight from the asset data
        guard let data = data(name), let image: CacheType = .init(data: data) else {
            return nil
        }

        // 3) If we were able to load the image data, stick it in the cache
        ImageCache.shared.insert(image, for: name)
        return .init(cacheType: image)
    }
}

/// Provides an image cache that holds the platform specific cache types (NSImage on macOS and UIImage for other platforms).
final class ImageCache: @unchecked Sendable {

    /// The shared image cache.
    static let shared: ImageCache = ImageCache()

    private lazy var cache: NSCache<AnyObject, CacheType> = {
        let cache = NSCache<AnyObject, CacheType>()
        cache.countLimit = countLimit
        return cache
    }()

    private let lock = NSLock()

    fileprivate func insert(_ image: CacheType, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.setObject(image, forKey: key as AnyObject)
    }

    fileprivate func image(for key: String) -> CacheType? {
        lock.lock()
        defer { lock.unlock() }
        return cache.object(forKey: key as AnyObject)
    }

    fileprivate subscript(_ key: String) -> CacheType? {
        image(for: key)
    }
}

fileprivate extension Image {

    /// Convenience initializer that takes an argument of the typealias CacheType.
    /// - Parameter cacheType: the cache type (NSImage on macOS and UIImage for other platforms)
    init(cacheType: CacheType) {
        #if os(macOS)
        self.init(nsImage: cacheType)
        #else
        self.init(uiImage: cacheType)
        #endif
    }
}
