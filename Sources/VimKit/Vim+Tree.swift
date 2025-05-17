//
//  Vim+Tree.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Foundation

extension Vim {

    /// Represents a skeleton model tree structure.
    public struct Tree: Equatable, Sendable {

        /// The root node of the tree.
        public var root: Node

        /// Holds a slice of tree data
        public struct Node: Equatable, Hashable, Sendable, Searchable {

            /// The name of the data slice
            public var name: String

            /// Adhere to searchable protocol
            public var searchableString: String { name }

            /// The id of this node directly contains. -1 indicates an invalid id.
            public var id: Int = .empty

            /// The that are contained in the data slice
            public var children: [Node]? = nil

            // Returns a union of all decendant child ids
            public var ids: Set<Int> {
                guard let children else { return .init([id]).subtracting([.empty]) }
                return children.reduce(.init([id])) { $0.union($1.ids).subtracting([.empty]) }
            }

            /// Recursively finds the first child or descendant with the specified name
            public func child(_ name: String) -> Node? {
                guard let children else { return nil }
                for child in children {
                    if child.name == name {
                        return child
                    } else if let descendant = child.child(name) {
                        return descendant
                    }
                }
                return nil
            }
        }

        /// Recursively searches the node tree for children that match the specified name.
        /// - Parameter name: the name to search for
        /// - Returns: a list of nodes sorted by their score
        public func search(_ name: String, minScore: Double = 0.5) -> [(item: Node, score: Double)] {
            let start = Date.now
            defer {
                let timeInterval = abs(start.timeIntervalSinceNow)
                debugPrint("Tree searched in [\(timeInterval.stringFromTimeInterval())]")
            }
            var results = [(item: Node, score: Double)]()
            search(name, node: root, results: &results)
            return results.sorted{ $0.score > $1.score }.filter{ $0.score > minScore }
        }

        /// Recursively searches the children of the given node that match the specified name.
        /// - Parameters:
        ///   - name: the name to search for
        ///   - node: the node to search
        ///   - results: the results to append to
        private func search(_ name: String, node: Node, results: inout [(item: Node, score: Double)]) {
            guard let children = node.children, children.isNotEmpty else { return }
            guard let searchResults = children.search(name), searchResults.isNotEmpty else { return }
            results.append(contentsOf: searchResults)
            // Stop searching if we have an exact match
            if searchResults.first?.score == 1.0 { return }
            for child in children {
                search(name, node: child, results: &results)
            }
        }
    }

}
