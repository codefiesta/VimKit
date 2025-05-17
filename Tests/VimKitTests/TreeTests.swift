//
//  TreeTests.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Foundation

import Testing
@testable import VimKit

@Suite("Tree Tests",
       .tags(.model))
class TreeTests {

    @Test("Verify Tree")
    func verifyTree() async throws {

        let root = Vim.Tree.Node(name: "root", children: [
            Vim.Tree.Node(name: "Doors", children: [
                Vim.Tree.Node(name: "Single Flush", children: [
                    Vim.Tree.Node(name: "900 x 2100mm", children: [
                        Vim.Tree.Node(name: "900 x 2100mm [1]", id: 1),
                        Vim.Tree.Node(name: "900 x 2100mm [2]", id: 2),
                        Vim.Tree.Node(name: "900 x 2100mm [3]", id: 3),
                    ])
                ])
            ]),
            Vim.Tree.Node(name: "Walls", children: [
                Vim.Tree.Node(name: "Basic Wall", children: [
                    Vim.Tree.Node(name: "Generic - 100mm", children: [
                        Vim.Tree.Node(name: "Generic - 100mm [4]", id: 4),
                        Vim.Tree.Node(name: "Generic - 100mm [5]", id: 5),
                        Vim.Tree.Node(name: "Generic - 100mm [6]", id: 6),
                    ]),
                    Vim.Tree.Node(name: "Concrete Garden Wall", children: [
                        Vim.Tree.Node(name: "Concrete Garden Wall [7]", id: 7),
                        Vim.Tree.Node(name: "Concrete Garden Wall [8]", id: 8),
                        Vim.Tree.Node(name: "Concrete Garden Wall [9]", id: 9),
                    ])
                ])
            ])
        ])

        let tree = Vim.Tree(root: root)

        #expect(tree.root.ids.count == 9)
        #expect(tree.root.child("Doors")!.ids == .init([1, 2, 3]))
        #expect(tree.root.child("Single Flush")!.ids == .init([1, 2, 3]))
        #expect(tree.root.child("Walls")!.ids.count == 6)
        #expect(tree.root.child("Basic Wall")!.ids.count == 6)
        #expect(tree.root.child("Generic - 100mm")!.ids == .init([4, 5, 6]))
        #expect(tree.root.child("Concrete Garden Wall")!.ids == .init([7, 8, 9]))
    }

}
