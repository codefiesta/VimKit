//
//  Geometry+Mesh.swift
//  VimKit
//
//  Created by Kevin McKee
//
import MetalKit
import simd

extension Geometry {

    public class Instance {

        /// The identifier of the instance
        public let idenitifer: Int
        /// 4x4 row-major matrix representing the node's world-space transform
        public let matrix: float4x4
        /// The first bit of each flag designates whether the instance should be initially hidden (1) or not (0) when rendered.
        public let flags: Int16
        /// Marks the instance as hidden
        public var hidden: Bool = false
        /// Marks the instance as selected
        public var selected: Bool = false
        /// Flag indicating if the instance is transparent or not.
        public var transparent: Bool = false
        /// A reference to the parent instance
        public weak var parent: Instance?
        /// The mesh information
        public var mesh: Mesh?

        /// A computed axis aligned bounding box from all of the submesh vertices or nil if this instance contains no mesh.
        public var boundingBox: MDLAxisAlignedBoundingBox?

        /// Returns the longest edge of this instance
        public var longestEdge: Float {
            return boundingBox?.longestEdge ?? .zero
        }

        /// Initializes the instance.
        /// 
        /// - Parameters:
        ///   - identifier: the instance unique identifier. Use this to find instances
        ///     within the geometry rather than the subscript as
        ///     the array of instances will most likely be sorted differently.
        ///   - matrix: The 4x4 row-major matrix representing the node's world-space transform
        ///   - flags: Holds the flags for the given instance.
        init(identifier: Int, matrix: float4x4 = .identity, flags: Int16) {
            self.idenitifer = identifier
            self.matrix = matrix
            self.flags = flags
            self.hidden = flags != .zero
        }
    }

    /// A mesh is composed of 0 or more submeshes.
    public struct Mesh: Equatable, Hashable {

        /// The range of submeshes contained inside this mesh.
        ///
        /// Can be used to find it's containing submeshes.
        /// For example: `let submeshes = geometry.submeshes[mesh.submeshes]`
        public let submeshes: Range<Int>?

        /// Initializes the mesh.
        ///
        /// - Parameters:
        ///   - submeshes: The range of submeshes contained inside this mesh
        init(submeshes: Range<Int>? = nil) {
            self.submeshes = submeshes
        }
    }

    public struct Submesh {

        /// The range of values in the index buffer to define the geometry of its triangular faces in local space.
        ///
        /// For example: `let indices = geometry.indices[submesh.indices]`
        public var indices: Range<Int>

        /// The submesh's byte offset into the index buffer.
        public var indexBufferOffset: Int {
            return indices.lowerBound * MemoryLayout<UInt32>.size
        }

        /// The mesh material.
        public var material: Material?

        /// Initializes the submesh.
        ///
        /// - Parameters:
        ///   - indices: The range of values in the index buffer.
        ///   - material: The submesh's material.
        init(indices: Range<Int>, material: Material? = nil) {
            self.indices = indices
            self.material = material
        }
    }

    /// A type that holds material information.
    public struct Material {

        /// The material glossiness in the domain of [0.0...0.1]
        public var glossiness: Float = .zero

        /// The material smoothness in the domain of [0.0...0.1]
        public var smoothness: Float = .zero

        /// The material RGBA diffuse color with components in the domain of [0.0...0.1]
        public var rgba: SIMD4<Float> = .zero
    }

    /// A type that holds geometric shape information.
    public struct Shape {

        /// The shape RGBA color with components in the domain of [0.0...0.1]
        public var rgba: SIMD4<Float> = .zero

        /// The width of the shape
        public var width: Float

        /// References a slice of vertices in the shape vertex buffer.
        ///
        /// For example: `let vertices = geometry.shapeVertexBuffer[shape.indices]`
        public var indices: Range<Int>
    }
}
