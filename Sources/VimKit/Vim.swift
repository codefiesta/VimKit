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
public class Vim: NSObject, ObservableObject, @unchecked Sendable {

    /// Represents the state of our file
    public enum State: Equatable, Sendable {
        case unknown
        case downloading
        case downloaded
        case loading
        case ready
        case error(String)
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

    @MainActor @Published
    public var state: State = .unknown

    /// The private pass through event publisher.
    private var eventPublisher = PassthroughSubject<Event, Never>()

    /// Provides a pass through subject used to broadcast events to downstream subscribers.
    /// The subject will automatically drop events if there are no subscribers, or its current demand is zero.
    @MainActor
    public lazy var events = eventPublisher.eraseToAnyPublisher()

    /// Progress Reporting for reading, mapping, and indexing the file.
    @MainActor
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

    /// The camera
    public var camera: Camera

    /// A set of options to apply.
    @Published
    public var options: Options

    /// The source url of the file.
    public var url: URL? = nil

    /// BFast Data Container
    private var bfast: BFast!

    /// Convenience var for accessing the SHA 256 hash of this file.
    public lazy var sha256Hash: String = {
        bfast.sha256Hash
    }()

    /// Convenience var for accessing the buffer names sorted alphabetically.
    @MainActor
    public lazy var bufferNames: [String] = {
        assert(state == .ready, "Misuse - wait until the file is ready before you can read buffer data.")
        return bfast.buffers.map { $0.name }
    }()

    /// Returns the total bytes in this VIM file.
    @MainActor
    public lazy var totalByteSize: Int = {
        assert(state == .ready, "Misuse - wait until the file is ready before you can read buffer data.")
        return bfast.totalByteSize
    }()

    /// Initializes the vim file.
    override public init() {
        self.camera = .init()
        self.options = .init()
    }

    /// Loads the vim file from the remote source file url.
    /// - Parameters:
    ///   - url: the source url of the vim file
    public func load(from url: URL) async {
        self.camera = .init()
        self.url = url
        await download()
    }

    /// Downloads the vim file if the file isn't already cached.
    /// The downloader checks the sha256Hash of the source file to see if we have a file with that name in the cache directory.
    /// If no file exist it will be downloaded, otherwise the file will be loaded from it's local cached file url.
    private func download() async {
        // Reset the file state to unknown as a renderer may be currently running.
        publish(state: .unknown)

        guard let url else {
            return publish(state: .error("💀 No url provided."))
        }

        do {
            switch url.scheme {
            case "https":
                publish(state: .downloading)
                let localURL = try await Vim.Downloader.shared.download(url: url, delegate: self)
                publish(state: .downloaded)
                await load(localURL)
            case "file":
                publish(state: .downloaded)
                await load(url)
            default:
                publish(state: .error("💀 Unable to handle url scheme [\(url.scheme ?? "")], please use file:// or https:// scheme"))
                return
            }
        } catch let error {
            publish(state: .error("💀 \(error)"))
        }
    }

    /// Loads the VIM file.
    /// - Parameters:
    ///   - url: the local url of the vim file
    private func load(_ url: URL) async {

        publish(state: .loading)

        guard let bfast = BFast(url) else {
            publish(state: .error("💀 Not a bfast file"))
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
                incrementProgressCount()
            case "assets":
                guard let container = BFast(buffer: buffer) else {
                    publish(state: .error("💀 Assets buffer is not a bfast container"))
                    return
                }
                assets = Assets(container)
                incrementProgressCount()
            case "entities":
                guard let container = BFast(buffer: buffer) else {
                    publish(state: .error("💀 Entities buffer is not a bfast container"))
                    return
                }
                db = Database(container, self)
                incrementProgressCount()
            case "strings":
                strings = String(data: buffer.data, encoding: .utf8)?.split(separator: "\0").map { String($0)} ?? []
                strings.insert("", at: 0) // TODO: Bug? The indexes are off by 1
                incrementProgressCount()
            case "geometry":
                guard let container = BFast(buffer: buffer) else { return }
                geometry = Geometry(container)
                incrementProgressCount()
            default:
                break
            }
        }

        debugPrint("􀇺 [Vim] - validated [\(bfast.header)]")

        // Put the file into a ready state
        publish(state: .ready)
    }

    /// Removes the contents of the locally cached vim file.
    public func remove() {
        defer {
            publish(state: .unknown)
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

    /// Publishes the vim file state onto the main thread.
    /// - Parameter state: the new state to publish
    private func publish(state: State) {
        Task { @MainActor in
            self.state = state
        }
    }

    /// Increments the progress count by the specfied number of completed units on the main thread.
    /// - Parameter count: the number of units completed
    private func incrementProgressCount(_ count: Int64 = 1) {
        Task { @MainActor in
            progress.completedUnitCount += count
        }
    }
}

public extension Vim {

    /// Returns the byte size of the buffer with the specified name.
    func bufferByteSize(name: String) -> Int {
        bfast.bufferByteSize(name: name)
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
        strings.indices.contains(index) ? strings[index] : nil
    }
}

extension Vim: URLSessionTaskDelegate {

    public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {

        Task { @MainActor in
            self.progress.addChild(task.progress, withPendingUnitCount: 1)
        }
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
    @MainActor
    public func select(id: Int, point: SIMD3<Float> = .zero) {
        guard let geometry else { return }
        let selected = geometry.select(id: id)
        eventPublisher.send(.selected(id, selected, 1, point))
    }

    /// Toggles an instance hidden state for the instance with the specified id
    /// and publishes an even to any subscribers.
    /// - Parameters:
    ///   - id: the ids of the instances to hide
    @MainActor
    public func hide(ids: [Int]) async {
        guard let geometry else { return }
        let hiddenCount = geometry.hide(ids: ids)
        eventPublisher.send(.hidden(hiddenCount))
    }

    /// Unhides all hidden instances.
    @MainActor
    public func unhide() async {
        guard let geometry else { return }
        geometry.unhide()
        eventPublisher.send(.hidden(0))
    }
}
