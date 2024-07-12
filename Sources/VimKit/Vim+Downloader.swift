//
//  Vim+Downloader.swift
//
//
//  Created by Kevin McKee
//

import Foundation

private let urlSessionIdentifier = "vim.downloader"

extension Vim {

    public enum DownloadError: Error {
        case error(String)
    }

    class Downloader: NSObject, URLSessionDelegate {

        static let shared: Downloader = Downloader()

        private var delegateQueue: OperationQueue {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 3
            queue.qualityOfService = .userInitiated
            return queue
        }

        private lazy var urlSession: URLSession = {
            // TODO: Allow background downloading
            // let configuration = URLSessionConfiguration.background(withIdentifier: urlSessionIdentifier)
            let configuration = URLSessionConfiguration.default
            return URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
        }()

        /// Downloads the file, caches it, and returns the locally cached file url.
        func download(url: URL, delegate: (URLSessionTaskDelegate)? = nil) async throws -> URL {
            // Check if the file exists on disk first
            let cacheDir = FileManager.default.cacheDirectory
            let localFileURL = cacheDir.appending(path: url.sha256Hash)

            if url.isCached {
                debugPrint("🎯 Cache hit [\(url.absoluteString)]")
                return localFileURL
            } else {
                debugPrint("❌ Cache miss [\(localFileURL.path)]")
            }

            // Download the file
            let urlRequest = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
            let (downloadedURL, response) = try await urlSession.download(for: urlRequest, delegate: delegate)

            // Make sure we actually received a file
            guard response.isOK else {
                // Remove the cached response
                URLCache.shared.removeCachedResponse(for: urlRequest)
                // Remove the downloaded item
                try? FileManager.default.removeItem(at: downloadedURL)
                throw DownloadError.error("Unable to download [\(url.absoluteString)] Status code[\(String(describing: response.statusCode()))]")
            }
            // Move the file contents into our cache directory
            do {
                try FileManager.default.moveItem(at: downloadedURL, to: localFileURL)
            } catch let error {
                debugPrint("💀", error)
            }
            return localFileURL
        }
    }
}
