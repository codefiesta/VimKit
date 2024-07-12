//
//  FileHandle+Extensions.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Foundation

extension FileHandle {

    /// Reads data from the specified offset up to the length of
    /// memory layout of the specifed type.
    /// - Parameters:
    ///     - fileOffset: the offset to seek in the file
    /// - Returns: The pointer value of the specified type
    func unsafeType<T>(_ fileOffset: UInt64? = nil) -> T? {
        if let offset = fileOffset {
            do {
                try seek(toOffset: offset)
            } catch {
                debugPrint("💩 unable to seek to \(offset): \(error)")
                return nil
            }
        }

        guard let data = try? read(upToCount: MemoryLayout<T>.size) else { return nil }
        let result: T? = data.unsafeType()
        return result
    }

    /// Returns the data at the specified offset up to the specified number of bytes as a typed array.
    /// - Parameters:
    ///   - fileOffset: the file offset to seek to
    ///   - count: the number of bytes to read from the file offset
    /// - Returns: a typed array from the data
    func unsafeTypeArray<T>(_ fileOffset: UInt64? = nil, count: Int) -> [T] {

        if let offset = fileOffset {
            do {
                try seek(toOffset: offset)
            } catch {
                debugPrint("💩 unable to seek [\(offset)]: \(error)")
                return []
            }
        }

        do {
            guard let data = try read(upToCount: MemoryLayout<T>.size *  count) else { return [] }
            let result: [T] = data.unsafeTypeArray(count)
            return result
        } catch {
            debugPrint("💩 unable to read data: \(error)")
            return []
        }
    }

    /// Reads the file data at the specified offset up to the specified number of bytes
    /// - Parameters:
    ///   - offset: the file offset to seek to
    ///   - count: the number of bytes to read from the file offset
    /// - Returns: the data block read from the from the offset to the specifed number of bytes
    func read(offset: UInt64, count: Int) -> Data? {
        do {
            try seek(toOffset: offset)
            return try read(upToCount: count)
        } catch {
            debugPrint("💩 unable to read data [\(offset):\(count)]: \(error)")
            return nil
        }
    }

    /// Reads the file data at the specified offset up to the specified number of bytes and mmap's the data into a cache file.
    /// - Parameters:
    ///   - offset: the offset to seek the file handle to
    ///   - count: the number of bytes to read from the offset
    ///   - fileName: the file's unique name
    /// - Returns: the mmap'd data
    func readMapped(offset: UInt64, count: Int, _ fileName: String) -> Data? {
        let cacheDir = FileManager.default.cacheDirectory
        let cacheFile = cacheDir.appending(path: fileName)
        if !FileManager.default.fileExists(atPath: cacheFile.path) {
            // Copy the bytes into the the cache file
            let data = read(offset: offset, count: count)
            try? data?.write(to: cacheFile)
        }
        return try? Data(contentsOf: cacheFile, options: .alwaysMapped)
    }
}
