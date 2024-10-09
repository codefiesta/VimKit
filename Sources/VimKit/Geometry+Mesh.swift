////
////  Geometry+Mesh.swift
////  VimKit
////
////  Created by Kevin McKee
////
import MetalKit
import VimKitShaders

/// Inverts the relationship between an Instance and a Mesh that allows us to draw using instancing.
class InstancedMesh {

    /// The mesh index that is shared across the instances.
    let mesh: Int
    /// Flag indicating if the mesh is transparent or not
    let transparent: Bool
    /// The instance indexes.
    let instances: [Int]
    /// Provides an offset into the instances buffer.
    var baseInstance: Int

    /// Initalizes the instanced mesh.
    /// - Parameters:
    ///   - mesh: the index of the mesh that should be instanced
    ///   - transparent: a flag indicating if the instance is transparent or not (used primarily for sorting).
    ///   - instances: the instance indexes
    ///   - baseInstance: the offset used by the GPU used to lookup the starting index into the instances buffer.
    init(mesh: Int32, transparent: Bool, instances: [Int], _ baseInstance: Int = 0) {
        self.mesh = Int(mesh)
        self.transparent = transparent
        self.instances = instances
        self.baseInstance = baseInstance
    }
}

extension Instance {

    /// Convenience var that returns the bounding box.
    var boundingBox: MDLAxisAlignedBoundingBox {
        .init(maxBounds: maxBounds, minBounds: minBounds)
    }

    /// Convenience var that returns the longest edge
    var longestEdge: Float {
        boundingBox.longestEdge
    }

    /// Initializer.
    /// - Parameters:
    ///   - index: the instance index
    ///   - matrix: the 4x4 row-major matrix representing the node's world-space transform
    ///   - flags: The first bit of each flag designates whether the instance should be initially hidden (1) or not (0) when rendered.
    ///   - parent: the parent index (-1 indicates no parent)
    ///   - mesh: the mesh index (-1 indicates this instance has no mesh)
    ///   - transparent: Flag indicating if the instance is transparent or not.
    init(index: Int, matrix: float4x4, flags: Int16, parent: Int32, mesh: Int32, transparent: Bool) {
        self.init(index: index,
                  colorIndex: .empty,
                  matrix: matrix,
                  state: flags != .zero ? .hidden : .default,
                  minBounds: .zero,
                  maxBounds: .zero,
                  parent: Int(parent),
                  mesh: Int(mesh),
                  transparent: transparent
        )
    }
}

extension Mesh {

    /// Initializes the mesh with a Swift range.
    /// A mesh is composed of 0 or more submeshes.
    ///
    /// Can be used to find it's containing submeshes.
    /// For example: `let submeshes = geometry.submeshes[mesh.submeshes]`
    /// - Parameter range: the range of submeshes contained in this mesh.
    init(_ range: Range<Int>) {
        self.init(submeshes: .init(range))
    }
}

extension Submesh {

    /// The submesh's byte offset into the index buffer.
    public var indexBufferOffset: Int {
        Int(indices.lowerBound) * MemoryLayout<UInt32>.size
    }

    /// Initializes the submesh.
    ///
    /// The indices can be used to lookup the values inside the index buffer.
    /// For example: `let indices = geometry.indices[submesh.indices]`
    /// - Parameters:
    ///   - material: The submesh's material index (-1 denotes no material).
    ///   - indices: The range of values in the index buffer.
    init(_ material: Int32, _ indices: Range<Int>) {
        self.init(material: Int(material), indices: .init(indices))
    }
}
