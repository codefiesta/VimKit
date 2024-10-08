//
//  Geometry+Spatial.swift
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

    /// Provides a bounding sphere used for intersection testing.
    struct Sphere {
        /// The center of the sphere.
        let center: SIMD3<Float>
        /// The sphere radius.
        let radius: Float

        /// Returns true if the given box is either inside or intersects this sphere.
        /// See: https://theorangeduck.com/page/correct-box-sphere-intersection
        /// - Parameter box: the box to check for intersections againts
        /// - Returns: true if intersects, otherwise false.
        func contains(box: MDLAxisAlignedBoundingBox) -> Bool {
            let r2 = powf(radius, 2)
            let closest = center.clamped(lowerBound: box.minBounds, upperBound: box.maxBounds)
            let d = distance_squared(center, closest)
            return d <= r2
        }
    }

    /// Every single 3D model is made out of the same three elements: vertices, edges, and faces.
    /// A vertex is a single point in space. When you connect two vertices, you've created an edge and if
    /// you connect three or more vertices in a closed loop, then you've created a face. A face is basically a polygon.
    struct Face {
        // Point a
        let a: SIMD3<Float>
        // Point b
        let b: SIMD3<Float>
        // Point c
        let c: SIMD3<Float>
    }
}

// MARK: Scene Graph

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
            root.box
        }

        /// Intializes the bounding volume with the specified geometry.
        /// - Parameter geometry: the geomety to use
        init(_ geometry: Geometry) async {
            self.geometry = geometry
            var data = [(index: Int, box: MDLAxisAlignedBoundingBox)]()
            for (i, instance) in geometry.instances.enumerated() {
                guard instance.boundingBox != .zero else { continue }
                data.append((index: i, box: instance.boundingBox))
            }
            root = Node(&data)
        }

        /// Traverses the BVH tree and accumulates a list of indices into the `geometry.instancedMeshes` array
        /// that are visible on the view frustum and should be rendered,
        /// See: https://www.flipcode.com/archives/Frustum_Culling.shtml
        /// - Parameter camera: the camera data
        /// - Returns: a list of indices into the `geometry.instancedMeshes` array that are inside the frustum
        func intersectionResults(camera: Vim.Camera) -> [Int] {
            guard let geometry else { return [] }
            var results = Set<Int>()
            intersections(camera: camera, node: root, results: &results)
            results.subtract(geometry.hiddeninstancedMeshes) // Remove any hidden instanced meshes
            return results.sorted()
        }

        /// Recursively iterates through the BVH nodes to collect results that are inside the given frustum.
        /// - Parameters:
        ///   - camera: the camera data
        ///   - node: the node to recursively look through
        ///   - results: the results to append to
        fileprivate func intersections(camera: Vim.Camera, node: Node, results: inout Set<Int>) {
            guard let geometry, camera.contains(node.box) else { return }
            let indices = node.instances.compactMap{ geometry.instancedMeshesMap[$0] }
            results.formUnion(indices)
            for child in node.children {
                intersections(camera: camera, node: child, results: &results)
            }
        }
    }
}
