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

/// The maximum number of indexes that should be contained in this node.
private let nodeThreshold = 8

extension Geometry {

    typealias BVH = BoundingVolumeHierarchy

    /// A type that holds a tree structure for geometry data used to build
    /// a spatial index and perform raycasting to quickly find intersecting geometry
    struct BoundingVolumeHierarchy {

        struct Node {

            /// The axis aligned bounding box that fully contains the geometry in this node.
            var box: MDLAxisAlignedBoundingBox
            /// The instanced mesh indexes that are contained in this node
            var instances = [Int]()
            /// The child nodes
            var children = [Node]()
            /// A flag denoting whether the node is a leaf.
            var isLeaf: Bool = false

            /// Initializer
            init(_ data: inout [(index: Int, box: MDLAxisAlignedBoundingBox)]) {
                self.box = MDLAxisAlignedBoundingBox(containing: data.map { $0.box })
                if data.count > nodeThreshold {

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

        /// Provides a hash lookup of instance indices into their instanced meshes index.
        private var instancedMeshesMap = [Int: Int]()

        /// Intializes the bounding volume with the specified geometry.
        /// - Parameter geometry: the geomety to use
        init(_ geometry: Geometry) async {
            self.geometry = geometry
            var data = [(index: Int, box: MDLAxisAlignedBoundingBox)]()
            for (i, instance) in geometry.instances.enumerated() {

                if let box = instance.boundingBox {
                    data.append((index: i, box: box))
                } else {
                    guard let box = await geometry.calculateBoundingBox(instance) else { continue }
                    data.append((index: i, box: box))
                }
            }

            // Map the instances to their shared meshes
            for (i, instancedMesh) in geometry.instancedMeshes.enumerated() {
                for j in instancedMesh.instances {
                    guard instancedMeshesMap[Int(j)] == nil else {
                        continue
                    }
                    instancedMeshesMap[Int(j)] = i
                }
            }

            root = Node(&data)
        }

        /// Accumulates frustum intersection results and returns a list of indices into the
        /// `geometry.instancedMeshes` array that are visible on the view frustum and should be rendered,
        /// - Parameter frustum: the view frustum
        /// - Returns: a list of indices into the `geometry.instancedMeshes` array that are inside the frustum
        func intersectionResults(frustum: Vim.Camera.Frustum) -> [Int] {
            var results = Set<Int>()
            intersections(frustum: frustum, node: root, results: &results)
            return results.sorted()
        }

        /// Recursively iterates through the BVH nodes to collect results that are inside the frustum planes.
        /// - Parameters:
        ///   - planes: the view frustum planes
        ///   - node: the node to recursively look through
        ///   - results: the results to append to
        fileprivate func intersections(frustum: Vim.Camera.Frustum, node: Node, results: inout Set<Int>) {
            guard intersects(frustum: frustum, node.box) else { return }
            var indices = node.instances.compactMap{ instancedMeshesMap[$0] }
            results.formUnion(indices)
            for child in node.children {
                intersections(frustum: frustum, node: child, results: &results)
            }
        }

        /// Tests to see if the viewing frustum planes false iinside or intersects the provided bounding box.
        /// See: https://iquilezles.org/articles/frustumcorrect/
        /// - Parameters:
        ///   - box: the bounding box to test
        ///   - planes: the viewing frustum planes
        /// - Returns: false if fully outside, true if inside or intersects
        fileprivate func intersects(frustum: Vim.Camera.Frustum, _ box: MDLAxisAlignedBoundingBox) -> Bool {
            for plane in frustum.planes {
                for corner in box.corners {
                    // Return true if any of the box corners are inside the frustum
                    if dot(corner, plane.xyz) > .zero {
                        return true
                    }
                }
            }
            return false
        }
    }
}
