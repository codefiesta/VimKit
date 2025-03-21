//
//  Assets+Cache.swift
//  VimKit
//
//  Created by Kevin McKee
//

import SwiftUI

#if os(macOS)
private typealias CacheType = NSImage
#else
private typealias CacheType = UIImage
#endif

// The maximum number of objects the cache should hold.
private let countLimit = 100

extension Assets {

    /// Fetches the asset with the give name as an image.
    /// - Parameter name: the name of the asset
    /// - Returns: the asset image
    public func image(from name: String?) -> Image? {

        guard let name else { return nil }
        let cacheKey = sha256Hash + "." + name

        // 1) Try to fetch the image straight out of the cache
        if let image = ImageCache.shared[cacheKey] {
            return .init(cacheType: image)
        }

        // 2) Try and load the image straight from the asset data
        guard let data = data(name), let image: CacheType = .init(data: data) else {
            return nil
        }

        // 3) If we were able to load the image data, stick it in the cache
        ImageCache.shared.insert(image, for: cacheKey)
        return .init(cacheType: image)
    }
}

/// Provides a singleton asset image cache that holds the platform specific
/// cache types (NSImage on macOS and UIImage for other platforms).
final class ImageCache: @unchecked Sendable {

    /// The shared image cache.
    static let shared: ImageCache = ImageCache()

    fileprivate lazy var cache: Cache<String, CacheType> = {
        let cache = Cache<String, CacheType>()
        cache.countLimit = countLimit
        return cache
    }()

    fileprivate func insert(_ image: CacheType, for key: String) {
        cache.insert(image, for: key)
    }

    fileprivate func value(for key: String) -> CacheType? {
        cache.value(for: key)
    }

    fileprivate subscript(_ key: String) -> CacheType? {
        cache[key]
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

    /// Initialization wrapper.
    /// - Parameters:
    ///   - cacheType: the platform specific cache type (NSImage or UIImage)
    ///   - path: the image content path
    init?(cacheType: CacheType, path: String) {
        guard let image: CacheType = .init(contentsOfFile: path) else { return nil }
#if os(macOS)
        self.init(nsImage: image)
#else
        self.init(uiImage: image)
#endif
    }

}

public extension Image {

    /// Attempt to load an image from a cached file.
    /// - Parameter file: the name of the cached file
    init?(file name: String?) {
        guard let name else { return nil }

        let cacheKey = name

        // 1) Try to fetch the image straight out of the cache
        if let image = ImageCache.shared[cacheKey] {
            self.init(cacheType: image)
            return
        }

        // 2) Try and create the image straight from the file contents
        let fileURL = FileManager.default.cacheDirectory.appending(path: cacheKey)
        guard FileManager.default.fileExists(atPath: fileURL.path),
            let image: CacheType = .init(contentsOfFile: fileURL.path) else {
            return nil
        }

        // Insert the image into the cache
        ImageCache.shared.insert(image, for: cacheKey)

        self.init(cacheType: image)
    }
}
