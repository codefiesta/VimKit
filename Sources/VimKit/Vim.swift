//
//  Vim.swift
//  VimKit
//
//  Created by Kevin McKee
//
import Combine
import Foundation

/// The Vim Data format
/// see: https://github.com/vimaec/vim
public class Vim: NSObject, ObservableObject {

    /// Represents the state of our file
    public enum State: Equatable {
        case unknown
        case initializing
        case downloading
        case loading
        case ready
        case error(String)
    }

    /// Keys and values used to specify loading or runtime options.
    public struct Option: Hashable, Equatable, RawRepresentable, @unchecked Sendable {

        public var rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// Represnts a broadcastable event that can be published to downstream subscribers.
    public enum Event: Equatable {

        /// A placeholder empty event that can be used to erase any downstream state.
        case empty

        /// An instance has been selected or deselected.
        /// - Parameter Int: the instance identifer
        /// - Parameter Bool: true if the instance has been selected, false if de-selected.
        /// - Parameter Int: the total count of selected instances.
        /// - Parameter SIMD3<Float>: the 3D positon of the selected object.
        case selected(Int, Bool, Int, SIMD3<Float>)

        /// An instance has been hidden or shown.
        /// - Parameter Int: the total count of hidden instances.
        case hidden(Int)
    }

    @Published
    public var state: State = .unknown

    /// The private pass through event publisher.
    private var eventPublisher = PassthroughSubject<Event, Never>()

    /// Provides a pass through subject used to broadcast events to downstream subscribers.
    /// The subject will automatically drop events if there are no subscribers, or its current demand is zero.
    public lazy var events = eventPublisher.eraseToAnyPublisher()

    /// Progress Reporting for reading, mapping, and indexing the file.
    public dynamic let progress = Progress(totalUnitCount: 5)

    /// See: https://github.com/vimaec/vim#header-buffer
    public var header = [String: String]()

    /// See: https://github.com/vimaec/vim#strings-buffer
    public var strings = [String]()

    /// See: https://github.com/vimaec/vim#entities-buffer
    public var db: Database?

    /// See: https://github.com/vimaec/vim/#assets-buffer
    public var assets: Assets?

    /// See: https://github.com/vimaec/vim#geometry-buffer
    public var geometry: Geometry?

    /// The dictionary of loading and runtime options to apply.
    public var options: [Option: Bool] = [:]

    /// The camera
    public var camera: Camera

    /// BFast Data Container
    private var bfast: BFast!

    /// Convenience var for accessing the SHA 256 hash of this file.
    public lazy var sha256Hash: String = {
        return bfast.sha256Hash
    }()

    /// Convenience var for accessing the buffer names sorted alphabetically.
    public lazy var bufferNames: [String] = {
        assert(state == .ready, "Misuse - wait until the file is ready before you can read buffer data.")
        return bfast.buffers.map { $0.name }
    }()

    /// Returns the total bytes in this VIM file.
    public lazy var totalByteSize: Int = {
        assert(state == .ready, "Misuse - wait until the file is ready before you can read buffer data.")
        return bfast.totalByteSize
    }()

    /// Initializes the VIM file from the specified url
    /// - Parameters:
    ///   - url: the url of the vim file
    ///   - options: the options to apply
    public init(_ url: URL, options: [Option: Bool]? = nil) {
        self.camera = Camera()
        self.options = options ?? [.xRay: false, .wireFrame: false]
        super.init()
        Task {
            await self.initialize(url)
        }
    }

    /// Initialixes the VIM file from the specified URL.
    /// - Parameters:
    ///   - url: the url of the vim file
    private func initialize(_ url: URL) async {
        do {
            switch url.scheme {
            case "https":
                DispatchQueue.main.async {
                    self.state = .downloading
                }
                let localURL = try await Vim.Downloader.shared.download(url: url, delegate: self)
                self.load(localURL)
            case "file":
                self.load(url)
            default:
                DispatchQueue.main.async {
                    self.state = .error("💀 Unable to handle url scheme [\(url.scheme ?? "")], please use file:// or https:// scheme")
                }
                return
            }
        } catch let error {
            DispatchQueue.main.async {
                self.state = .error("💀 \(error)")
            }
        }
    }

    /// Loads the VIM file.
    /// - Parameters:
    ///   - url: the local url of the vim file
    private func load(_ url: URL) {

        DispatchQueue.main.async {
            self.state = .loading
        }
        guard let bfast = BFast(url) else {
            DispatchQueue.main.async {
                self.state = .error("💀 Not a bfast file")
            }
            return
        }
        self.bfast = bfast

        for buffer in bfast.buffers {
            switch buffer.name {
            case "header":
                let headerEntries = String(data: buffer.data, encoding: .utf8)?.split(separator: "\n") ?? []
                for headerEntry in headerEntries {
                    let entry = headerEntry.split(separator: "=")
                    header[String(entry[0])] = String(entry[1])
                }
                progress.completedUnitCount += 1
            case "assets":
                guard let container = BFast(buffer: buffer) else {
                    state = .error("💀 Assets buffer is not a bfast container")
                    return
                }
                assets = Assets(container)
                progress.completedUnitCount += 1
            case "entities":
                guard let container = BFast(buffer: buffer) else {
                    state = .error("💀 Entities buffer is not a bfast container")
                    return
                }
                db = Database(container, self)
                progress.completedUnitCount += 1
            case "strings":
                strings = String(data: buffer.data, encoding: .utf8)?.split(separator: "\0").map { String($0)} ?? []
                strings.insert("", at: 0) // TODO: Bug? The indexes are off by 1
                progress.completedUnitCount += 1
            case "geometry":
                guard let container = BFast(buffer: buffer) else { return }
                geometry = Geometry(container)
                progress.completedUnitCount += 1
            default:
                break
            }
        }

        debugPrint("􀇺 [Vim] - validated [\(bfast.header)]")

        // Put the file into a ready state
        DispatchQueue.main.async {
            self.state = .ready
        }
    }

    /// Removes the contents of the locally cached vim file.
    public func remove() {
        defer {
            DispatchQueue.main.async {
                self.state = .unknown
            }
        }

        var hashes = [String]([sha256Hash])
        guard let geometry, let db else { return }
        geometry.cancel()
        db.cancel()

        hashes.append(geometry.sha256Hash)
        hashes.append(db.sha256Hash)

        let cacheDirectory = FileManager.default.cacheDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path()) else { return }

        for file in files {
            for hash in hashes {
                if file.contains(hash) {
                    let url = FileManager.default.cacheDirectory.appending(path: file)
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    /// Validates the VIM file.
    private func validate() {

        guard let nodeTable = db?.Node else {
            assert(false, "The node table doesn't exist in the database")
            return
        }

        var count = nodeTable.count
        guard let geometry = geometry else {
            assert(false, "The geometry block is absent")
            return
        }

        guard let materialsTable = db?.Material else {
            assert(false, "The materials table doesn't exist in the database")
            return
        }

        count = materialsTable.count
        assert(geometry.materialColors.count == count, "The number of material colors doesn't match the materials count.")
        assert(geometry.materialGlossiness.count == count, "The number of material glossiness doesn't match the materials count.")
        assert(geometry.materialSmoothness.count == count, "The number of material smoothness doesn't match the materials count.")

        guard let shapesTable = db?.Shape else {
            assert(false, "The shapes table doesn't exist in the database")
            return
        }

        count = shapesTable.count
        assert(geometry.shapeVertexOffsets.count == count, "The number of shape vertex offsets doesn't match the shapes count.")
        assert(geometry.shapeColors.count == count, "The number of shape colors doesn't match the shapes count.")
        assert(geometry.shapeWidths.count == count, "The number of shape widths doesn't match the shapes count.")
    }
}

public extension Vim {

    /// Returns the byte size of the buffer with the specified name.
    func bufferByteSize(name: String) -> Int {
        assert(state == .ready, "Misuse - wait until the file is ready before you can read buffer data.")
        return bfast.bufferByteSize(name: name)
    }
}

/// Provides a protcol interface for looking up an indexed string
protocol IndexedStringDataProvider: AnyObject {

    /// Returns a string at the specified index or nil if the index is invalid.
    /// - Parameter index: the array index of the string to return
    /// - Returns: a string from the valid specified index or nil if the index is invalid
    func string(at index: Int) -> String?
}

extension Vim: IndexedStringDataProvider {

    func string(at index: Int) -> String? {
        return strings.indices.contains(index) ? strings[index] : nil
    }
}

extension Vim: URLSessionTaskDelegate {

    public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        self.progress.addChild(progress, withPendingUnitCount: 0)
    }
}

// MARK: Event Interactions

extension Vim {

    /// Erases a previous published event to downstream event subscribers.
    public func erase() {
        eventPublisher.send(.empty)
    }

    /// Toggles an instance selection state for the instance with the specified id.
    /// - Parameters:
    ///   - id: the id of the instance to select (or deselect if already selected).
    ///   - point: the point in 3D space where the object was selected
    public func select(id: Int, point: SIMD3<Float> = .zero) {
        guard let geometry else { return }
        let selected = geometry.select(id: id)
        DispatchQueue.main.async {
            // Publish the selection event
            self.eventPublisher.send(.selected(id, selected, 1, point))
        }
    }

    /// Toggles an instance hidden state for the instance with the specified id
    /// and publishes an even to any subscribers.
    /// - Parameters:
    ///   - id: the ids of the instances to hide
    public func hide(ids: [Int]) async {
        guard let geometry else { return }
        let hiddenCount = geometry.hide(ids: ids)
        DispatchQueue.main.async {
            // Publish the hidden event
            self.eventPublisher.send(.hidden(hiddenCount))
        }
    }

    /// Unhides all hidden instances.
    public func unhide() async {
        guard let geometry else { return }
        geometry.unhide()
        DispatchQueue.main.async {
            // Publish the hidden event
            self.eventPublisher.send(.hidden(0))
        }
    }
}

// MARK: Options

public extension Vim.Option {

    /// A key used to specify whether wireframing or fill mode should be applied.
    static let wireFrame: Vim.Option = .init(rawValue: "wireFrame")

    /// A key used to specify whether the file should be rendered in xray mode or not.
    static let xRay: Vim.Option = .init(rawValue: "xRay")
}
