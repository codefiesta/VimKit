//
//  BFast.swift
//  VimKit
//
//  Created by Kevin McKee
//

import CryptoKit
import Foundation

/// The BFast format is essentially a collection of named data buffers (byte arrays).
struct BFast: Hashable {

    // The header magic validation
    fileprivate static let MAGIC = 0xBFA5

    // 32 Bytes
    public struct Header: Hashable {
        let magic: UInt64
        let dataStart: UInt64
        let dataEnd: UInt64
        let numberOfBuffers: UInt64 // Number of all buffers
    }

    // 16 Bytes
    public struct Range {
        let begin: UInt64
        let end: UInt64
        var count: Int {
            Int(end - begin)
        }

        var isValid: Bool {
            begin < end
        }
    }

    public struct Buffer: Hashable {
        let name: String
        let data: Data

        /// Common Initializer.
        /// - Parameters:
        ///   - name: the name of the buffer
        ///   - data: the buffer data
        init(name: String, data: Data) {
            self.name = name
            self.data = data
        }

        /// Initializes the buffer with mmap'd data from the specified file within the specified range.
        /// - Parameters:
        ///   - file: the file handle to the buffer data
        ///   - range: the range of buffer data to mmap
        ///   - sha256Hash: the buffer's container SHA 256 hash
        ///   - name: the name of the buffer.
        fileprivate init?(file: FileHandle, range: Range, _ sha256Hash: String, _ name: String) {
            let fileName = [sha256Hash, name].joined(separator: ".")
            guard let data = file.readMapped(offset: range.begin, count: range.count, fileName) else {
                return nil
            }
            self.name = name
            self.data = data
        }

        /// Initializes the buffer with the specified data block and attempts to mmap the data into it's own file.
        /// - Parameters:
        ///   - data: the data block
        ///   - sha256Hash: the unique sha256Hash
        ///   - name: the name of the buffer.
        fileprivate init?(data: Data, _ sha256Hash: String, _ name: String) {
            let fileName = [sha256Hash, name].joined(separator: ".")
            guard let mmapped = data.mmap(fileName) else { return nil }
            self.name = name
            self.data = mmapped
        }
    }

    /// The container header.
    let header: Header
    /// The buffers contained inside this container.
    let buffers: [Buffer]
    /// The SHA 256 hash of this container
    let sha256Hash: String

    /// Returns the total bytes of this container
    public lazy var totalByteSize: Int = {
        var total: Int = .zero
        for buffer in buffers {
            total += buffer.data.count
        }
        return total
    }()

    /// Initializes the BFast container from the specified file path
    ///
    /// - Parameters:
    ///   - url: The local file url
    init?(_ url: URL) {

        guard let file = try? FileHandle(forReadingFrom: url) else {
            debugPrint("💩 Unable to load file handle from url [\(url)]")
            return nil
        }

        defer {
            try? file.close()
        }

        // 1) Read the header
        guard let header: Header = file.unsafeType(), header.magic == BFast.MAGIC else {
            debugPrint("💩 Not a BFast file")
            return nil
        }
        self.header = header
        self.sha256Hash = url.lastPathComponent

        assert(header.numberOfBuffers > 0, "The number of buffers is invalid")

        // 2) Read the buffer data ranges
        // See: https://github.com/vimaec/vim-format/blob/develop/docs/bfast.md#ranges-section
        let ranges: [Range] = file.unsafeTypeArray(count: Int(header.numberOfBuffers))
        assert(ranges.count == header.numberOfBuffers, "The number of byte ranges doesn't match the number of buffers")

        var names = [String]()
        var buffers = [Buffer]()

        for (i, range) in ranges.enumerated() {
            guard let slice = file.read(offset: range.begin, count: range.count) else { break }
            if i == 0 {
                // The first buffer is always the array of names
                names = slice.toStringArray()
            } else {
                let name = names[i-1]
                guard let buffer = Buffer(data: slice, sha256Hash, name) else { continue }
                buffers.append(buffer)
            }
        }

        /// See: https://github.com/vimaec/vim#names-buffer
        assert(names.count == header.numberOfBuffers - 1, "The number of names must equal the number of buffers - 1")
        self.buffers = buffers

    }

    /// Initializes the BFast container from the specified buffer.
    ///
    /// It's important to call `.subdata(in: Range)` instead of simply subscripting child buffer data in order 
    /// to reset any resulting child buffer data indices.
    /// Although `.subdata` returns a new copy of the data in this range which bloats memory (but can be offset by mmapping),
    /// the indices in a subscript slice are copied from the original data block that can/will crash child buffers when slicing.
    /// For more info on this subject see https://forums.swift.org/t/data-subscript/57195
    ///
    /// - Parameters:
    ///   - buffer: The data buffer that holds a BFast container
    init?(buffer: Buffer) {
        guard let header: Header = buffer.data.unsafeType(), header.magic == BFast.MAGIC else {
            debugPrint("💩 Not a BFast file")
            return nil
        }
        self.header = header
        self.sha256Hash = buffer.data.sha256Hash

        // Read the buffer data ranges - They always start at byte 32 right after the header
        let offset = MemoryLayout<Header>.size
        let data = buffer.data.slice(offset: offset)
        let ranges: [Range] = data.unsafeTypeArray(Int(header.numberOfBuffers))
        assert(ranges.count == header.numberOfBuffers, "The number of byte ranges doesn't match the number of buffers")

        var names = [String]()
        var buffers = [Buffer]()

        for (i, range) in ranges.enumerated() {
            guard range.isValid else { continue } // Ignore any zero byte ranges

            let slice = buffer.data.subdata(in: Int(range.begin)..<Int(range.end))
            if i == 0 {
                // The first buffer is always the array of names
                names = slice.toStringArray()
            } else {
                let name = names[i-1]
                // Mmap the data slice to it's own file
                if slice.count >= Data.minMmapByteSize {
                    guard let b = Buffer(data: slice, sha256Hash, name) else { continue }
                    buffers.append(b)
                } else {
                    let b = Buffer(name: name, data: slice)
                    buffers.append(b)
                }
            }
        }

        /// See: https://github.com/vimaec/vim#names-buffer
        assert(names.count == header.numberOfBuffers - 1, "The number of names must equal the number of buffers - 1")
        self.buffers = buffers
    }

    /// Returns the byte size of the buffer with the specified name.
    public func bufferByteSize(name: String) -> Int {
        if let buffer = buffers.filter({ $0.name == name }).first {
            return buffer.data.count
        }
        return .zero
    }
}

fileprivate extension Data {

    /// Converts this data into a string array.
    /// - Returns: an array of strings
    func toStringArray() -> [String] {
        String(data: self, encoding: .utf8)?.split(separator: "\0").map { String($0)} ?? []
    }

    /// Returns a slice of this data block from the specified range.
    /// - Parameter range: the bfast data range
    /// - Returns: a data slice
    func slice(range: BFast.Range) -> Data {
        let r = Int(range.begin)..<Int(range.end)
        return self[r]
    }
}
