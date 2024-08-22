//
//  Database.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Combine
import Foundation
import SwiftData

/// The sqlite file extension of database
private let sqliteExtension = ".sqlite"

// See: https://github.com/vimaec/vim#entities-buffer
@dynamicMemberLookup
public class Database: ObservableObject {

    @dynamicMemberLookup
    public class Table {

        /// Table Column
        public class Column: Identifiable {

            enum DataType: String {
                case byte // 8 bit value, typically used for booleans
                case index // 32-bit signed integer used to reference a relation to a row in another table
                case int // 32-bit signed integer
                case string // The strings column is a Int32 which is used as the index into the strings buffer
                case double // 64-bit double-precision floating point values
                case long // 64-bit signed integer
                case float // 32-bit single-precision floating point values
            }

            /// Identifiable id
            public var id: String {
                return name
            }

            /// The name of the column
            public let name: String
            /// The name of the reference table (if the dataType is an index)
            public let index: String?
            /// The type of values the column stores
            let dataType: DataType
            /// The data buffer that contains the coiumn data
            private let buffer: BFast.Buffer
            /// The string data provider used to peform string lookups
            private weak var stringDataProvider: IndexedStringDataProvider?

            /// Initializes the column.
            ///
            /// - Parameters:
            ///   - buffer: The data buffer that holds the column data
            ///   - stringDataProvider: The string data provider
            init?(_ buffer: BFast.Buffer, _ stringDataProvider: IndexedStringDataProvider) {
                self.buffer = buffer
                self.stringDataProvider = stringDataProvider
                let descriptor = buffer.name.components(separatedBy: ":")
                guard let dataType = DataType(rawValue: descriptor[0]) else { return nil }
                self.dataType = dataType
                self.name = descriptor.last!
                self.index = dataType == .index ? descriptor[1].replacingOccurrences(of: ".", with: "") : nil
            }

            /// Returns the raw data as an array
            /// TODO: This can be made more memory effecient
            lazy var rows: [AnyHashable] = {
                switch dataType {
                case .byte:
                    let results: [UInt8] = buffer.data.unsafeTypeArray()
                    return results
                case .index, .int:
                    let results: [Int32] = buffer.data.unsafeTypeArray()
                    return results
                case .string:
                    let results: [Int32] = buffer.data.unsafeTypeArray()
                    let strings = results.map { stringDataProvider?.string(at: Int($0)) ?? .empty }
                    return strings
                case .double:
                    let results: [Double] = buffer.data.unsafeTypeArray()
                    return results
                case .long:
                    let results: [Int64] = buffer.data.unsafeTypeArray()
                    return results
                case .float:
                    let results: [Float] = buffer.data.unsafeTypeArray()
                    return results
                }
            }()

            /// Returns the number of rows inside the column.
            /// See: https://github.com/vimaec/vim#entities-buffer
            var count: Int {
                switch self.dataType {
                case .byte:
                    return Int(self.buffer.data.count / MemoryLayout<UInt8>.size)
                case .index, .int, .string:
                    return Int(self.buffer.data.count / MemoryLayout<Int32>.size)
                case .double:
                    return Int(self.buffer.data.count / MemoryLayout<Double>.size)
                case .long:
                    return Int(self.buffer.data.count / MemoryLayout<Int64>.size)
                case .float:
                    return Int(self.buffer.data.count / MemoryLayout<Float>.size)
                }
            }
        }

        /// The columns inside this table
        var columns = [String: Column]()
        /// The data buffer that contains the table data
        private let buffer: BFast.Buffer

        /// Initializes the table.
        ///
        /// - Parameters:
        ///   - buffer: The data buffer that holds the table data
        ///   - stringDataProvider: The string data provider
        init?(_ buffer: BFast.Buffer, _ stringDataProvider: IndexedStringDataProvider) {
            self.buffer = buffer
            guard let bfast = BFast(buffer: buffer) else { return nil }
            // The columns of the table are encoded as BFast buffers
            for (_, buffer) in bfast.buffers.enumerated() {
                guard let column = Column(buffer, stringDataProvider) else { continue }
                columns[column.name.replacingOccurrences(of: ".", with: "")] = column
            }
            // Validate the table
            validate()
        }

        /// Validates the table to ensure all colums have the same row count.
        private func validate() {
            // Validate the rows in all of the columns have the same count
            var counts = [Int]()
            guard columns.isNotEmpty else { return }
            for (_, column) in columns {
                counts.append(column.count)
            }
            let set = Set(counts)
            assert(set.count == 1, "The number of rows in the columns aren't equal")
        }

        /// The name of the table
        public var name: String {
            return buffer.name
        }

        /// Returns the number of rows this table has
        public var count: Int {
            return columns.values.first?.count ?? 0
        }

        /// Dynamic subscipt to use `.dot syntax` for referencing a table column
        subscript(dynamicMember member: String) -> Column? {
            return columns[member]
        }

        /// Convenience var for accessing the table colum names sorted alphabetically.
        public lazy var columnNames: [String] = {
            let names = Array(columns.keys)
            return names.sorted { $0 < $1 }
        }()

        /// Fetches the column data inside the table
        public func select(_ columnNames: [String]? = nil) -> [Column] {
            var results = [Column]()
            // Filter columns
            if let columnNames = columnNames {
                for name in columnNames {
                    if let column = columns[name] {
                        results.append(column)
                    }
                }
            } else {
                // Include all all columns
                for (_, column) in columns {
                    results.append(column)
                }
            }
            return results
        }
    }

    /// The tables contained inside this buffer
    var tables = [String: Table]()
    /// The encapsulating data buffer
    let bfast: BFast
    /// Cancellable tasks.
    var tasks = [Task<(), Never>]()

    /// Convenience var for accessing the SHA 256 hash of this database data.
    public lazy var sha256Hash: String = {
        return bfast.sha256Hash
    }()

    /// The SwiftData model container
    public var modelContainer: ModelContainer

    /// The private pass through result set publisher.
    private var resultSetPublisher = PassthroughSubject<ResultSet, Never>()

    /// Provides a pass through subject used to broadcast result sets.
    /// The subject will automatically drop events if there are no subscribers, or its current demand is zero.
    public lazy var results = resultSetPublisher.eraseToAnyPublisher()

    /// Initializes the database with the specified BFast container.
    ///
    /// - Parameters:
    ///   - bfast: The container that holds the entity data.
    ///   - stringDataProvider: The string data provider
    init(_ bfast: BFast, _ stringDataProvider: IndexedStringDataProvider) {
        self.bfast = bfast

        // Register the value transformers
        Database.registerValueTransformers()

        let cacheDir = FileManager.default.cacheDirectory
        let containerURL = cacheDir.appending(path: "\(bfast.sha256Hash)\(sqliteExtension)")

        let schema = Schema(Database.allTypes)
        let configuration = ModelConfiguration(schema: schema, url: containerURL)
        debugPrint("􁗫 [Model Container] - [\(containerURL)]")

        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: configuration)
        } catch let error {
            fatalError("💀 \(error)")
        }

        // Each buffer is contains a table
        for (_, buffer) in bfast.buffers.enumerated() {
            guard let table = Table(buffer, stringDataProvider) else { continue }
            tables[table.name.replacingOccurrences(of: "Vim.", with: "")] = table
        }
    }

    /// Convenience var for accessing the table names sorted alphabetically.
    public lazy var tableNames: [String] = {
        let names = Array(tables.keys)
        return names.sorted { $0 < $1 }
    }()

    /// Dynamic subscipt to use `.dot syntax` for referencing tables
    ///
    /// Allows callers to dynamically reference tables names.
    ///
    /// `let table = entites.VimGeometry`.
    subscript(dynamicMember member: String) -> Table? {
        return tables[member]
    }
}

// MARK: Database Queries (Raw Data)

extension Database {

    /// Fetches the raw table data.
    /// - Parameters:
    ///   - tableName: The name of the table to fetch data from
    public func select(_ tableName: String? = nil) {

        guard let tableName, let table = tables[tableName] else { return }

        Task {
            let resultSet = ResultSet(table)
            DispatchQueue.main.async {
                self.resultSetPublisher.send(resultSet)
            }
        }
    }
}

@dynamicMemberLookup
public struct ResultSet: RandomAccessCollection, Sequence {

    public typealias Element = [String: AnyHashable]

    public typealias Index = Int

    public typealias Indices = CountableRange<Int>

    public var startIndex: Int {
        return rows.startIndex
    }

    public var endIndex: Int {
        return rows.endIndex
    }

    public var count: Int {
        return rows.count
    }

    public subscript(position: Int) -> [String: AnyHashable] {
        return rows[position]
    }

    public subscript(dynamicMember member: String) -> String? {
        return member
    }

    public let tableName: String
    public let columnNames: [String]
    fileprivate let columns: [Database.Table.Column]
    fileprivate var rows = [[String: AnyHashable]]()

    init(_ table: Database.Table) {
        self.tableName = table.name
        self.columns = Array(table.columns.values)
        self.columnNames = columns.map { $0.name }.sorted { $0 < $1 }

        let count = columns.first?.count ?? 0
        for i in 0..<count {
            var row = [String: AnyHashable]()
            for column in columns {
                row[column.name] = column.rows[i]
            }
            rows.append(row)
        }
    }

    init(_ tableName: String, _ colums: [Database.Table.Column]) {
        self.tableName = tableName
        self.columns = colums
        self.columnNames = columns.map { $0.name }.sorted { $0 < $1 }

        let count = columns.first?.count ?? 0
        for i in 0..<count {
            var row = [String: AnyHashable]()
            for column in columns {
                row[column.name] = column.rows[i]
            }
            rows.append(row)
        }
    }

    public static func == (lhs: ResultSet, rhs: ResultSet) -> Bool {
        return lhs.tableName == rhs.tableName && lhs.count == rhs.count
    }
}

struct ResultSetIterator: IteratorProtocol {

    private let resultSet: ResultSet
    private let count: Int
    private var index: Int

    init(_ resultSet: ResultSet) {
        self.resultSet = resultSet
        self.index = 0
        self.count = resultSet.columns.first?.count ?? 0
    }

    mutating func next() -> [String: AnyHashable]? {
        guard index < count else { return nil }
        var row = [String: AnyHashable]()
        for column in resultSet.columns {
            row[column.name] = column.rows[index]
        }
        index += 1
        return row
    }
}
