//
//  URL+Extensions.swift
//  
//
//  Created by Kevin McKee
//

import CryptoKit
import Foundation

public extension URL {

    /// Calculates the SHA hash of an url
    var sha256Hash: String {
        let hashed = SHA256.hash(data: Data(self.absoluteString.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Returns true if the file is locally cached or not
    var isCached: Bool {
        switch self.scheme {
        case "https":
            return FileManager.default.fileExists(atPath: cacheURL.path)
        case "file":
            return true
        default:
            return false
        }
    }

    /// Returns the locally cache file url.
    var cacheURL: URL {
        switch self.scheme {
        case "https":
            let cacheDir = FileManager.default.cacheDirectory
            let cachedFileURL = cacheDir.appending(path: sha256Hash)
            return cachedFileURL
        case "file":
            return self
        default:
            return self
        }
    }

    /// Returns the cached file size in bytes..
    var cacheSize: Int64 {
        if isCached {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
                  let size = attributes[.size] as? Int64 else { return .zero }
            return size
        }
        return .zero
    }

    /// Convenience var that returns a formatted human readable string from  the cached file size byte count.
    var cacheSizeFormatted: String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useMB]
        bcf.countStyle = .file
        let string = bcf.string(fromByteCount: cacheSize)
        return string
    }
}

public extension URLResponse {

    var isOK: Bool {
        if let code = statusCode()  {
            return 200...299 ~= code
        }
        return false
    }

    func statusCode() -> Int? {
        if let httpResponse = self as? HTTPURLResponse {
            return httpResponse.statusCode
        }
        return nil
    }
}
