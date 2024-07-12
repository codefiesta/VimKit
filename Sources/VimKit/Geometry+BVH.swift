//
//  Geometry+BVH.swift
//  
//
//  Created by Kevin McKee
//

import Foundation
import MetalKit
import simd
import Spatial

extension Geometry {

    typealias BVH = BoundingVolumeHierarchy

    /// A type that holds a tree structure for geometry data used to build
    /// a spatial index and perform raycasting to quickly find intersecting geometry
    struct BoundingVolumeHierarchy {

        struct Node {

            /// The axis aligned bounding box that fully contains the geometry in this node.
            var box: MDLAxisAlignedBoundingBox
            /// The instance indexes that are contained in this node
            var instances = [Int]()
            /// The child nodes
            var children = [Node]()
            /// The maximum number of indexes that should be contained in this node.
            let threshold: Int = 8
            /// A flag denoting whether the node is a leaf.
            var isLeaf: Bool = false

            /// Initializer
            init(_ data: inout [(index: Int, box: MDLAxisAlignedBoundingBox)]) {
                self.box = MDLAxisAlignedBoundingBox(containing: data.map { $0.box })
                if data.count > threshold {

                    sort(&data)

                    let halfed = data.split()
                    var left = halfed.0
                    var right = halfed.1

                    if !left.isEmpty {
                        children.append(Node(&left))
                    }

                    if !right.isEmpty {
                        children.append(Node(&right))
                    }

                } else {
                    isLeaf = true
                    instances = data.map { $0.index }
                }
            }

            /// Sorts the nodes.
            @discardableResult
            private func sort(_ data: inout [(index: Int, box: MDLAxisAlignedBoundingBox)]) -> Axis3D {

                // The axis to sort on
                let axis = box.longestAxis

                // 2) Sort the data along largest axis
                data.sort {
                    switch axis {
                    case .x:
                        return $0.box.center.x < $1.box.center.x
                    case .y:
                        return $0.box.center.y < $1.box.center.y
                    case .z:
                        return $0.box.center.z < $1.box.center.z
                    default:
                        return $0.box.center.x < $1.box.center.x
                    }
                }
                return axis
            }
        }

        /// A weak reference to the geometry container.
        private weak var geometry: Geometry?

        /// The root node of the volume hierarchy
        private var root: Node

        /// Returns the bounds of the entire hierarchy
        var bounds: MDLAxisAlignedBoundingBox {
            return root.box
        }

        /// Intializes the bounding volume with the specified geometry.
        /// - Parameter geometry: the geomety to use
        init(_ geometry: Geometry) async {
            self.geometry = geometry
            var data = [(index: Int, box: MDLAxisAlignedBoundingBox)]()
            for (i, instance) in geometry.instances.enumerated() {
                if let box = instance.boundingBox {
                    data.append((index: i, box: box))
                }
            }
            root = Node(&data)
        }
    }
}
