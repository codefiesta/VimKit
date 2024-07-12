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
            let cacheDir = FileManager.default.cacheDirectory
            let localFileURL = cacheDir.appending(path: sha256Hash)
            return FileManager.default.fileExists(atPath: localFileURL.path)
        case "file":
            return true
        default:
            return false
        }
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
