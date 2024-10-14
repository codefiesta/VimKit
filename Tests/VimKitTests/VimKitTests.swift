import Combine
@testable import VimKit
import XCTest

final class VimKitTests: XCTestCase {

    private var subscribers = Set<AnyCancellable>()

    override func setUp() {
        subscribers.removeAll()
    }

    override func tearDown() {
        for subscriber in subscribers {
            subscriber.cancel()
        }
    }

    /// Tests loading a remote VIM file
    func testLoadRemoteFile() async throws {

        // Downloads the `residence.vim` from the VIM samples
        let urlString = "https://vim02.azureedge.net/samples/residence.v1.2.75.vim"
        let url = URL(string: urlString)!
        let vim: Vim = .init()

        // Subscribe to the file state
        let readyExpection = expectation(description: "Ready")

        vim.$state.sink { state in
            switch state {
            case .unknown, .downloading, .downloaded, .loading, .error:
                debugPrint(state)
            case .ready:
                // The file is now ready to be read
                readyExpection.fulfill()
            }
        }.store(in: &subscribers)

        Task {
            await vim.load(from: url)
        }

        // Wait for the file to be downloaded and put into a ready state
        await fulfillment(of: [readyExpection], timeout: 30)
    }
}
