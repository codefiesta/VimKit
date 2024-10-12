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
        let urlString = "https://vim.azureedge.net/samples/residence.vim"
        let url = URL(string: urlString)!
        let vim = Vim(url)

        // Subscribe to the file state
        let readyExpection = self.expectation(description: "Ready")
        vim.$state.sink { state in
            switch state {
            case .unknown, .initializing, .downloading, .loading, .error:
                break
            case .ready:
                // The file is now ready to be read
                readyExpection.fulfill()
            }
        }.store(in: &subscribers)

        // Wait for the file to be downloaded and put into a ready state
        await fulfillment(of: [readyExpection], timeout: 30)
    }
}
