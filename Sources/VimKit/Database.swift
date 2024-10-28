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
public class Database: ObservableObject, @unchecked Sendable {

    public class Table {

        class Rows {

            /// Holds a hash of colums.
            let columns: [String: Column]

            /// Convenience var for accessing the table colum names sorted alphabetically.
            lazy var columnNames: [String] = {
                columns.keys.sorted { $0 < $1 }
            }()

            /// Returns the row count.
            var count: Int {
                columns.first?.value.rows.count ?? 0
            }

            /// Initializer.
            /// - Parameter columns: the colums hash
            init(columns: [String: Column]) {
                self.columns = columns
                validate()
            }

            /// Subscript that returns a single row hash of the column name and it's type erased at the specified index.
            subscript(index: Int) -> [String: AnyHashable] {
                var row = [String: AnyHashable]()
                for (key, column) in columns {
                    row[key] = column.rows[index]
                }
                return row
            }

            /// Validates the table to ensure all colums have the same row count.
            private func validate() {
                // Validate the rows in all of the columns have the same count
                var counts = [Int]()

                guard columns.isNotEmpty else { return }
                for (_, column) in columns {
                    counts.append(column.rows.count)
                }
                let set = Set(counts)
                assert(set.count == 1, "The number of rows in the columns aren't equal")
            }

        }

        /// Table Column
        public class Column: Identifiable {

            /// Column Data Wrapper that allows us to subscript the underlying storage
            protocol DataWrapper {

                /// Returns the number of rows in the column.
                var count: Int { get }

                /// Subscript that returns the storage data at the specified index as type erased data.
                subscript(index: Int) -> AnyHashable { get }
            }


            /// A Column Data wrapper that holds storage of the specified type.
            class TypedDataWrapper<T: Hashable>: DataWrapper {

                /// The colum data.
                let data: Data

                /// The total count of rows.
                var count: Int {
                    let storage: UnsafeBufferPointer<T> = data.toUnsafeBufferPointer()
                    return storage.count
                }

                /// Initializer.
                /// - Parameter data: the underlying storage data
                init(data: Data) {
                    self.data = data
                }

                /// Subscript that returns the storage data at the specified index as type erased data.
                subscript(index: Int) -> AnyHashable {
                    let storage: UnsafeBufferPointer<T> = data.toUnsafeBufferPointer()
                    return storage[index]
                }
            }

            /// A Column Data wrapper that holds storage of indices into the indexed string provider.
            class StringDataWrapper: TypedDataWrapper<Int32> {

                /// The indexed string provider.
                let stringDataProvider: IndexedStringDataProvider

                /// Initializer
                /// - Parameters:
                ///   - data: the storage data
                ///   - stringDataProvider: the indexed string data provider.
                init(data: Data, stringDataProvider: IndexedStringDataProvider) {
                    self.stringDataProvider = stringDataProvider
                    super.init(data: data)
                }

                /// Subscript that returns the storage data at the specified index as type erased data.
                override subscript(index: Int) -> AnyHashable {
                    let storage: UnsafeBufferPointer<Int32> = data.toUnsafeBufferPointer()
                    let i = Int(storage[index])
                    return stringDataProvider.string(at: i)
                }
            }

            /// The column data type
            enum DataType: String {
                /// 8 bit value, typically used for booleans
                case byte
                /// 32-bit signed integer used to reference a relation to a row in another table
                case index
                /// 32-bit signed integer
                case int
                /// The strings column is a Int32 which is used as the index into the strings buffer
                case string
                /// 64-bit double-precision floating point values
                case double
                /// 64-bit signed integer
                case long
                /// 32-bit single-precision floating point values
                case float
            }

            /// Identifiable id
            public var id: String {
                name
            }

            /// The name of the column
            public let name: String
            /// The name of the reference table (if the dataType is an index)
            public let index: String?
            /// The type of values the column stores
            let dataType: DataType
            /// The data buffer that contains the coiumn data
            private let buffer: BFast.Buffer
            /// The column data.
            let rows: DataWrapper

            /// Initializes the column.
            /// See: See: https://github.com/vimaec/vim#entities-buffer
            ///
            /// - Parameters:
            ///   - buffer: The data buffer that holds the column data
            ///   - stringDataProvider: The string data provider
            init?(_ buffer: BFast.Buffer, _ stringDataProvider: IndexedStringDataProvider) {
                self.buffer = buffer
                let descriptor = buffer.name.components(separatedBy: ":")
                guard let dataType = DataType(rawValue: descriptor[0]) else { return nil }
                self.dataType = dataType
                self.name = descriptor.last!
                self.index = dataType == .index ? descriptor[1].replacingOccurrences(of: ".", with: "") : nil
                switch dataType {
                case .byte:
                    self.rows = TypedDataWrapper<UInt8>(data: buffer.data)
                case .index, .int:
                    self.rows = TypedDataWrapper<Int32>(data: buffer.data)
                case .string:
                    self.rows = StringDataWrapper(data: buffer.data, stringDataProvider: stringDataProvider)
                case .double:
                    self.rows = TypedDataWrapper<Double>(data: buffer.data)
                case .long:
                    self.rows = TypedDataWrapper<Int64>(data: buffer.data)
                case .float:
                    self.rows = TypedDataWrapper<Float>(data: buffer.data)
                }
            }
        }

        /// The table rows
        var rows: Rows

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
            var columns = [String: Column]()
            // The columns of the table are encoded as BFast buffers
            for (_, buffer) in bfast.buffers.enumerated() {
                guard let column = Column(buffer, stringDataProvider) else { continue }
                let name = column.name.replacingOccurrences(of: ".", with: "")
                columns[name] = column
            }
            guard columns.isNotEmpty else { return nil }
            self.rows = Rows(columns: columns)
        }

        /// The name of the table
        public var name: String {
            buffer.name
        }

        /// Convenience var for accessing the table colum names sorted alphabetically.
        public var columns: [String] {
            rows.columnNames
        }

        /// Returns the number of rows this table has
        public var count: Int {
            rows.count
        }
    }

    /// Represents the observable state of our database.
    public enum State: Equatable, Sendable {
        case unknown
        case importing
        case ready
        case error(String)
    }

    @MainActor @Published
    public var state: State = .unknown

    /// The tables contained inside this buffer
    var tables = [String: Table]()

    /// The encapsulating data buffer
    let bfast: BFast

    /// Cancellable tasks.
    var tasks = [Task<(), Never>]()

    /// Convenience var for accessing the SHA 256 hash of this database data.
    public lazy var sha256Hash: String = {
        bfast.sha256Hash
    }()

    /// The SwiftData model container
    public var modelContainer: ModelContainer

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

    /// Publishes the database state onto the main thread.
    /// - Parameter state: the new state to publish
    func publish(state: State) {
        Task { @MainActor in
            self.state = state
        }
    }

    /// Convenience var for accessing the table names sorted alphabetically.
    public lazy var tableNames: [String] = {
        tables.keys.sorted { $0 < $1 }
    }()
}
