//
//  FileManager+Extensions.swift
//  
//
//  Created by Kevin McKee
//

import Foundation

private let cacheDirName = "cache"

extension FileManager {

    /// Returns the default cache directory
    var cacheDirectory: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        if let bundleIdentifier = Bundle.main.bundleIdentifier {

            let url = cacheDir.appending(path: bundleIdentifier).appending(path: cacheDirName)

            // Try and create the directory if it doesn't exist
            try? FileManager.default.createDirectory(atPath: url.path, withIntermediateDirectories: true, attributes: nil)

            return url
        }
        return cacheDir
    }
}
