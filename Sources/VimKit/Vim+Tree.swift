//
//  Vim+Tree.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Foundation

extension Vim {

    /// Represents a skeleton model tree structure.
    public struct Tree: Sendable {

        /// The root node of the tree.
        public var root: Node

        /// Holds a slice of tree data
        public struct Node: Equatable, Hashable, Sendable {
            /// The name of the data slice
            public var name: String
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
    }

}
