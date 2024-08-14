//
//  Geometry.swift
//  VimKit
//
//  Created by Kevin McKee
//
import Combine
import Foundation
import MetalKit
import simd

// File extensions for mmap'd metal buffers
private let normalsBufferExtension = ".normals"

/// See: https://github.com/vimaec/vim#geometry-buffer
/// This class was largely translated from VIM's CSharp + JS implementtions:
/// https://github.com/vimaec/g3d/blob/master/csharp/Vim.G3d/G3D.cs
/// https://github.com/vimaec/vim-ts/blob/develop/src/g3d.ts
public class Geometry: ObservableObject {

    /// Represents the state of our geometry buffer
    public enum State: Equatable {
        case loading
        case indexing
        case ready
        case error(String)
    }

    /// Progress Reporting for loading the geometry data.
    @objc public dynamic let progress = Progress(totalUnitCount: 8)

    @Published
    public var state: State = .loading

    /// Returns the combinded positions (vertex) buffer of all of the vertices for all the meshes layed out in slices of [x,y,z]
    public private(set) var positionsBuffer: MTLBuffer?
    /// Returns the combinded index buffer of all of the indices.
    public private(set) var indexBuffer: MTLBuffer?
    /// Returns the combinded buffer of all of the normals.
    public private(set) var normalsBuffer: MTLBuffer?
    /// Returns true if the geometry should be drawn using instancing.
    public private(set) var instancingEnabled: Bool = false

    /// The Geometry Bounding Volume Hierarchy
    var bvh: BVH?

    /// The data container
    private let bfast: BFast
    private var attributes = [Attribute]()

    /// Initializer
    init(_ bfast: BFast) {
        self.bfast = bfast
        for (index, buffer) in bfast.buffers.enumerated() {
            // Skip the first buffer as it is only meta information
            // See: https://github.com/vimaec/g3d/#meta-information
            if index > 0 {
                guard let descriptor = AttributeDescriptor(buffer.name) else {
                    debugPrint("💀", buffer.name)
                    continue
                }
                let attribute = Attribute(descriptor: descriptor, buffer: buffer)
                attributes.append(attribute)
            }
        }

        Task {
            await load()
        }
    }

    /// Asynchronously loads the geometry structures and Metal buffers.
    private func load() async {

        let device = MTLContext.device
        let cacheDir = FileManager.default.cacheDirectory

        // 1) Build the positions (vertex) buffer
        let positions = attributes(association: .vertex, semantic: .position)
        guard let positionsBuffer = positions.makeBufferNoCopy(device: device, type: Float.self) else {
            fatalError("💀 Unable to create positions buffer")
        }
        self.positionsBuffer = positionsBuffer
        progress.completedUnitCount += 1

        // 2) Build the index buffer
        let indices = attributes(association: .corner, semantic: .index)
        guard let indexBuffer = indices.makeBufferNoCopy(device: device, type: UInt32.self) else {
            fatalError("💀 Unable to create index buffer")
        }
        self.indexBuffer = indexBuffer
        progress.completedUnitCount += 1

        // 3) Build the normals buffer
        let normalsBufferFile = cacheDir.appending(path: "\(bfast.sha256Hash)\(normalsBufferExtension)")
        if !FileManager.default.fileExists(atPath: normalsBufferFile.path) {
            var normals = vertexNormals
            let data = Data(bytes: &normals, count: MemoryLayout<Float>.size * normals.count)
            try! data.write(to: normalsBufferFile)
        }

        guard let normalsBuffer = device.makeBufferNoCopy(normalsBufferFile, type: Float.self) else {
            fatalError("💀 Unable to create normals buffer")
        }
        self.normalsBuffer = normalsBuffer
        progress.completedUnitCount += 1

        // 5) Build all the data structures
        _ = materials // Build the materials
        progress.completedUnitCount += 1
        _ = submeshes // Build the submeshes
        progress.completedUnitCount += 1
        _ = meshes // Build the meshes
        progress.completedUnitCount += 1
        _ = instances // Build the instances
        progress.completedUnitCount += 1

        // Start indexing the file
        DispatchQueue.main.async {
            self.state = .indexing
        }

        Task {
            await bvh = BVH(self)
            progress.completedUnitCount += 1
            DispatchQueue.main.async {
                self.state = .ready
            }
        }
    }

    // MARK: Postions (Vertex Buffer Raw Data)

    /// Returns the combinded vertex buffer of all of the vertices for all the meshes layed out in slices of [x,y,z].
    public lazy var positions: UnsafeMutableBufferPointer<Float> = {
        assert(positionsBuffer != nil, "💩 Misuse [positions]")
        return positionsBuffer!.toUnsafeMutableBufferPointer()
    }()

    // MARK: Index Buffer

    /// Returns the combined index buffer of all the meshes (one index per corner, and per half-edge).
    /// The values in this index buffer are relative to the beginning of the vertex buffer.
    public lazy var indices: UnsafeMutableBufferPointer<UInt32> = {
        assert(indexBuffer != nil, "💩 Misuse [indices]")
        return indexBuffer!.toUnsafeMutableBufferPointer()
    }()

    // MARK: Vertices

    /// Calculates the vertex normals.
    /// TODO: Port this over to Metal Performance Shaders to perform this work on the GPU.
    /// - https://computergraphics.stackexchange.com/questions/4031/programmatically-generating-vertex-normals
    /// -  https://iquilezles.org/articles/normals/
    /// - Returns: an array of vertex normals
    var vertexNormals: [Float] {
        var results = [Float]()
        for normal in faceNormals {
            let n = normalize(normal)
            results.append(contentsOf: [n.x, n.y, n.z])
        }
        return results
    }

    lazy var vertexTangents: [SIMD4<Float>] = {
        var results = [SIMD4<Float>]()
        let attributes = attributes(association: .vertex, semantic: .tangent)
        for attribute in attributes {
            let array: [Float] = attribute.buffer.data.unsafeTypeArray()
            let values = array.chunked(into: 4).map { SIMD4<Float>($0) }
            results.append(contentsOf: values)
        }
        return results
    }()

    /// Represents the (U,V) values associated with each vertex used for texture mapping.
    lazy var vertexUVs: [Float] = {
        var results = [Float]()
        let attributes = attributes(association: .vertex, semantic: .uv)
        for attribute in attributes {
            let array: [Float] = attribute.buffer.data.unsafeTypeArray()
            results.append(contentsOf: array)
        }

        // TODO: Not sure what to do here - we can't create a buffer of zero length so create empty coordinates??
        if results.isEmpty {
            results = Array(repeating: Float.zero, count: positions.count / 3)
        }
        return results
    }()

    // MARK: Faces

    /// Material indices per face,
    lazy var faceMaterials: [Int32] = {
        let attributes = attributes(association: .face, semantic: .material)
        return attributes.data.unsafeTypeArray()
    }()

    /// If not provided, will be computed dynamically as the average of all vertex normals,
    /// NOTE: This is not lazy as we can truly discard it from memory once done with it.
    var faceNormals: [SIMD3<Float>] {
        var results = [SIMD3<Float>]()
        let attributes = attributes(association: .face, semantic: .normal)
        for attribute in attributes {
            let array: [Float] = attribute.buffer.data.unsafeTypeArray()
            let values = array.chunked(into: 3).map { SIMD3<Float>($0) }
            results.append(contentsOf: values)
        }

        // Compute the values
        if results.isEmpty {
            var faceNormals = positions.chunked(into: 3).map { _ in SIMD3<Float>.zero }
            let verices = positions.chunked(into: 3).map { SIMD3<Float>($0) }
            for i in stride(from: 0, to: indices.count, by: 3) {
                let a = verices[Int(indices[i])]
                let b = verices[Int(indices[i+1])]
                let c = verices[Int(indices[i+2])]
                let crossProduct = cross(b - a, c - a)

                faceNormals[Int(indices[i])] += crossProduct
                faceNormals[Int(indices[i+1])] += crossProduct
                faceNormals[Int(indices[i+2])] += crossProduct
            }
            results.append(contentsOf: faceNormals)
        }

        return results
    }

    // MARK: Meshes

    /// The index offsets of a submesh in a given mesh
    lazy var meshSubmeshOffsets: [Int32] = {
        let attributes = attributes(association: .mesh, semantic: .submeshoffset)
        return attributes.data.unsafeTypeArray()
    }()

    /// Constructs the meshes from their data blocks
    public lazy var meshes: [Mesh] = {
        var meshes = [Mesh]()

        for (i, offset) in meshSubmeshOffsets.enumerated() {

            // Calculate the range of submeshes contained inside this mesh
            let start = Int(offset)
            let nextOffset = i < meshSubmeshOffsets.endIndex - 1 ? meshSubmeshOffsets[Int(i+1)] : meshSubmeshOffsets.last!
            let end = i < meshSubmeshOffsets.endIndex - 1 ? Int(nextOffset): Int(meshSubmeshOffsets.last!)
            let submeshRange: Range<Int> = start..<end

            // Build the mesh
            let mesh = Mesh(submeshes: submeshRange)
            meshes.append(mesh)
        }
        return meshes
    }()

    // MARK: Submeshes

    /// References a slice of values in the index buffer to define the geometry of its triangular faces in local space.
    lazy var submeshIndexOffsets: [Int32] = {
        let attributes = attributes(association: .submesh, semantic: .indexoffset)
        return attributes.data.unsafeTypeArray()
    }()

    lazy var submeshMaterials: [Int32] = {
        let attributes = attributes(association: .submesh, semantic: .material)
        return attributes.data.unsafeTypeArray()
    }()

    ///  Constructs all of the Submeshes from their associated data blocks.
    public lazy var submeshes: [Submesh] = {
        var submeshes = [Submesh]()

        for (i, offset) in submeshIndexOffsets.enumerated() {

            // Calculate the range of values in the index buffer
            let start = Int(offset)
            let nextOffset = i < submeshIndexOffsets.endIndex - 1 ? submeshIndexOffsets[Int(i+1)] : submeshIndexOffsets.last!
            let end = i < submeshIndexOffsets.endIndex - 1 ? Int(nextOffset): Int(submeshIndexOffsets.last!)
            let indicesRange: Range<Int> = start..<end

            // Grab the submesh material (an empty value of -1 denotes no material)
            var material: Material?
            let materialsOffset = submeshMaterials[i]
            if materialsOffset != .empty {
                material = materials[Int(materialsOffset)]
            }

            let submesh = Submesh(indices: indicesRange, material: material)
            submeshes.append(submesh)
        }
        return submeshes
    }()

    // MARK: Instances

    /// Returns the instance flags
    lazy var instanceFlags: [Int16] = {
        let attributes = attributes(association: .instance, semantic: .flags)
        return attributes.data.unsafeTypeArray()
    }()

    /// Returns the index of a parent instance associated with a given instance
    lazy var instanceParents: [Int32] = {
        let attributes = attributes(association: .instance, semantic: .parent)
        return attributes.data.unsafeTypeArray()
    }()

    /// Returns the 4x4 row-major transform matrix values associated with their respective instances.
    lazy var instanceTransforms: [float4x4] = {
        var results = [float4x4]()
        let attributes = attributes(association: .instance, semantic: .transform)
        for attribute in attributes {
            let array: [Float] = attribute.buffer.data.unsafeTypeArray()
            let values = array.chunked(into: 16).map {
                simd_float4x4(
                    SIMD4<Float>($0[0], $0[1], $0[2], $0[3]),
                    SIMD4<Float>($0[4], $0[5], $0[6], $0[7]),
                    SIMD4<Float>($0[8], $0[9], $0[10], $0[11]),
                    SIMD4<Float>($0[12], $0[13], $0[14], $0[15])
                )
            }
            results.append(contentsOf: values)
        }
        return results
    }()

    /// Returns the Mesh associated with instances
    lazy var instanceMeshes: [Int32] = {
        let attributes = attributes(association: .instance, semantic: .mesh)
        return attributes.data.unsafeTypeArray()
    }()

    /// Builds the instances (nodes).
    public lazy var instances: [Instance] = {
        var instances = [Instance]()

        // Map the vertices once so we can calculate the bounding boxes
        let vertices = positions.chunked(into: 3).map { SIMD3<Float>($0) }

        // Build the base instances
        for (i, transform) in instanceTransforms.enumerated() {

            var flags: Int16 = 0
            if instanceFlags.indices.contains(i) {
                flags = instanceFlags[i]
            }

            let instance = Instance(identifier: i, matrix: transform, flags: flags)

            // Lookup the instance mesh
            let meshOffset = instanceMeshes[i]
            if meshOffset != .empty {
                instance.mesh = meshes[Int(meshOffset)]
            }

            // Calculate the bounding box of the instance async
            Task {
                await instance.boundingBox = calculateBoundingBox(instance, vertices)
            }
            instances.append(instance)
        }

        // Set the instance parent (if one)
        for (i, offset) in instanceParents.enumerated() {
            if offset != .empty {
                let parent = instances[Int(offset)]
                instances[i].parent = parent
            }
        }

        // Mark any transparent instances
        for instance in instances {
            guard let range = instance.mesh?.submeshes else {
                instance.transparent = true
                continue
            }

            // Find the lowest alpha value to determine transparency
            let alpha = range
                .map { submeshes[$0] }
                .sorted { $0.material?.rgba.w ?? .zero < $1.material?.rgba.w ?? .zero }
                .first?.material?.rgba.w ?? .zero
            instance.transparent = alpha < 1.0
        }

        // Finally, sort the instances by opaques and transparents
        instances.sort{ !$0.transparent && $1.transparent }
        return instances
    }()

    /// Convenience var that returns a count of the hidden instances.
    public var hiddenCount: Int {
        return instances.filter{ $0.hidden && $0.flags == .zero }.count
    }

    /// Convenience var that returns a count of the selected instances.
    public var selectedCount: Int {
        return instances.filter{ $0.selected }.count
    }

    /// Convenience method to find an instance by it's identifier.
    /// - Parameter identifier: the instance identifier
    /// - Returns: the instance with the specified identifier or nil if none found.
    public func instance(for identifier: Int) -> Instance? {
        return instances.filter({ $0.idenitifer == identifier }).first
    }

    /// Calculates the bounding box for the specified instance.
    /// - Parameters:
    ///   - instance: the instance to calculate the bounding box for
    ///   - vertices: the array of vertices
    /// - Returns: the axis aligned bounding box for the specified instance or nil if the instance has no mesh information.
    private func calculateBoundingBox(_ instance: Instance, _ vertices: [SIMD3<Float>]) async -> MDLAxisAlignedBoundingBox? {
        guard let mesh = instance.mesh, let range = mesh.submeshes else { return nil }
        var minBounds: SIMD3<Float> = .zero
        var maxBounds: SIMD3<Float> = .zero
        for submesh in submeshes[range] {
            for index in submesh.indices {
                if index < vertices.count {
                    let vertex = vertices[index]
                    minBounds = min(minBounds, vertex)
                    maxBounds = max(maxBounds, vertex)
                }
            }
        }
        return MDLAxisAlignedBoundingBox(maxBounds: maxBounds, minBounds: minBounds)
    }

    // MARK: Shapes

    lazy var shapeVertices: [SIMD3<Float>] = {
        var results = [SIMD3<Float>]()
        let attributes = attributes(association: .shape, semantic: .position)
        for attribute in attributes {
            let array: [Float] = attribute.buffer.data.unsafeTypeArray()
            let values = array.chunked(into: 3).map { SIMD3<Float>($0) }
            results.append(contentsOf: values)
        }
        return results
    }()

    lazy var shapeVertexCounts: Int = {
        return shapeVertices.count
    }()

    lazy var shapeVertexOffsets: [Int32] = {
        let attributes = attributes(association: .shape, semantic: .vertexoffset)
        return attributes.data.unsafeTypeArray()
    }()

    lazy var shapeIndexOffsets: [Int32] = {
        let attributes = attributes(association: .shape, semantic: .indexoffset)
        return attributes.data.unsafeTypeArray()
    }()

    lazy var shapeColors: [SIMD4<Float>] = {
        var results = [SIMD4<Float>]()
        let attributes = attributes(association: .shape, semantic: .color)
        for attribute in attributes {
            let array: [Float] = attribute.buffer.data.unsafeTypeArray()
            let values = array.chunked(into: 4).map { SIMD4<Float>($0) }
            results.append(contentsOf: values)
        }
        return results
    }()

    lazy var shapeWidths: [Float] = {
        let attributes = attributes(association: .shape, semantic: .width)
        return attributes.data.unsafeTypeArray()
    }()

    // MARK: Materials

    /// Returns the RGBA diffuse color of a given material in a value range of 0.0..1.0
    lazy var materialColors: [SIMD4<Float>] = {
        var results = [SIMD4<Float>]()
        let attributes = attributes(association: .material, semantic: .color)
        for attribute in attributes {
            let array: [Float] = attribute.buffer.data.unsafeTypeArray()
            let values = array.chunked(into: 4).map { SIMD4<Float>($0) }
            results.append(contentsOf: values)
        }
        return results
    }()

    /// Returns an array of values from 0.0..1.0 representing the glossiness of a given material.
    lazy var materialGlossiness: [Float] = {
        var results = [Float]()
        let attributes = attributes(association: .material, semantic: .glossiness)
        for attribute in attributes {
            let array: [Float] = attribute.buffer.data.unsafeTypeArray()
            results.append(contentsOf: array)
        }
        return results
    }()

    /// Returns an array of values from 0.0..1.0 representing the smoothness of a given material.
    lazy var materialSmoothness: [Float] = {
        var results = [Float]()
        let attributes = attributes(association: .material, semantic: .smoothness)
        for attribute in attributes {
            let array: [Float] = attribute.buffer.data.unsafeTypeArray()
            results.append(contentsOf: array)
        }
        return results
    }()

    ///  Constructs all of the Materials from their associated data blocks.
    public lazy var materials: [Material] = {
        var materials = [Material]()
        for (i, color) in materialColors.enumerated() {
            let glossiness = materialGlossiness[i]
            let smoothness = materialSmoothness[i]
            let material = Material(glossiness: glossiness, smoothness: smoothness, rgba: color)
            materials.append(material)
        }
        return materials
    }()

    /// Finds the attributes that have the specified association and semantic.
    /// - Parameters:
    ///   - association: the aatribute descriptotor association to match against
    ///   - semantic: the aatribute descriptotor semantic to match against
    /// - Returns: all attributes that match the soecified association and semantic
    fileprivate func attributes(association: AttributeDescriptor.Association, semantic: AttributeDescriptor.Semantic) -> [Attribute] {
        return attributes.filter { $0.descriptor.association == association && $0.descriptor.semantic == semantic }
    }
}
