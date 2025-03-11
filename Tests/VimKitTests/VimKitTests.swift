//
//  VimKitTests.swift
//
//
//  Created by Kevin McKee
//
import Foundation
import Testing
@testable import VimKit

/// Skip tests that require downloads on Github runners.
private let testsEnabled = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"] == nil

@Suite("File Reader Tests",
       .enabled(if: testsEnabled),
       .tags(.reader))
struct FileReaderTests {

    private let vim: Vim = .init()
    private let urlString = "https://storage.cdn.vimaec.com/samples/residence.v1.2.75.vim"
    private var url: URL {
        .init(string: urlString)!
    }

    @Test("downloading a vim file")
    func whenDownloading() async throws {
        await vim.load(from: url)
        await #expect(vim.state == .ready)
    }
}
