//
//  Data+Extensions.swift
//  VimKit
//
//  Created by Kevin McKee
//

import CryptoKit
import Foundation

extension Data {

    /// The min data size (in MB) used to determine if a data block should be mmap'd or not.
    static let minMmapByteSize = 1024 * 1000 * 8

    /// Calculates the SHA hash of this data
    var sha256Hash: String {
        let hashed = SHA256.hash(data: self)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Returns the data block as a raw byte array.
    var bytes: [UInt8] {
        [UInt8](self)
    }

    /// Convenience var that returns the byte count formatted into a human readable string.
    var byteCountFormatted: String {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useMB]
        bcf.countStyle = .file
        let string = bcf.string(fromByteCount: Int64(count))
        return string
    }

    /// Returns the data block as a single specified type.
    ///
    /// TODO: Validate the size of this data block against the MemoryLayout size of the specified type.
    func unsafeType<T>() -> T? {
        guard let result: UnsafePointer<T> = unsafePointer() else { return nil }
        return result.pointee
    }

    /// Unpacks the data into an array of the specified type.
    ///
    /// If a `count` isn't specified, the count will be determined by dividing the total number of
    /// bytes inside this data block by the memory layout size of the type.
    func unsafeTypeArray<T>(_ count: Int? = nil) -> [T] {
        let count = count ?? Int(self.count / MemoryLayout<T>.size)
        return withUnsafeBytes { (pointer) -> [T] in
            let buffer = UnsafeBufferPointer(start: pointer.baseAddress?.assumingMemoryBound(to: T.self), count: count)
            return Array(buffer)
        }
    }

    /// Builds an UnsafeMutableBufferPointer from the buffer contents of the specifed type.
    /// - Returns: a mutable buffer pointer of the specified type.
    func toUnsafeBufferPointer<T>() -> UnsafeBufferPointer<T> {
        withUnsafeBytes { (pointer) -> UnsafeBufferPointer<T> in
            pointer.bindMemory(to: T.self)
        }
    }

    /// Returns a new data buffer that is a slice of the current data.
    ///
    /// If a `count` isn't specified the new slice will go until the end of the data block.
    func slice(offset: Int, count: Int? = nil) -> Data {
        let end = count ?? bytes.count
        let range = offset..<end
        return self[range]
    }

    /// Attempts to mmap this data into the specified file
    /// - Parameters:
    ///   - fileName: the file's unique name
    /// - Returns: the mmap'd file data
    func mmap(_ fileName: String) -> Data? {
        let cacheDir = FileManager.default.cacheDirectory
        let cacheFile = cacheDir.appending(path: fileName)
        if !FileManager.default.fileExists(atPath: cacheFile.path) {
            // Copy the data into the the cache file
            try? self.write(to: cacheFile)
        }
        return try? Data(contentsOf: cacheFile, options: .alwaysMapped)
    }

    /// Returns the total count of elements for the specified type.
     /// - Parameter type: the data type to perform a count of
     /// - Returns: the total count of elements for the specified type
     func count<T>(of type: T.Type) -> Int {
         Int(self.count / MemoryLayout<T>.size)
     }
}

fileprivate extension Data {

    func unsafePointer<T>() -> UnsafePointer<T>? {
        let result = withUnsafeBytes { (pointer) -> UnsafePointer<T>? in
            pointer.baseAddress?.assumingMemoryBound(to: T.self)
        }
        return result
    }
}
