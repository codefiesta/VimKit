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
import VimKitShaders

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
    @objc public dynamic let progress = Progress(totalUnitCount: 9)

    @Published
    public var state: State = .loading

    /// Returns the combinded positions (vertex) buffer of all of the vertices for all the meshes layed out in slices of [x,y,z]
    public private(set) var positionsBuffer: MTLBuffer?
    /// Returns the combinded index buffer of all of the indices.
    public private(set) var indexBuffer: MTLBuffer?
    /// Returns the combinded buffer of all of the normals.
    public private(set) var normalsBuffer: MTLBuffer?
    /// Returns the combinded buffer of all of the instance transforms and their state information.
    public private(set) var instancesBuffer: MTLBuffer?

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

        // 4) Build all the data structures
        _ = materials // Build the materials
        progress.completedUnitCount += 1
        _ = submeshes // Build the submeshes
        progress.completedUnitCount += 1
        _ = meshes // Build the meshes
        progress.completedUnitCount += 1
        _ = instances // Build the instances
        progress.completedUnitCount += 1

        // 5) Build the instances buffer
        var instanced = instanceOffsets.map {
            Instances(index: $0,
                      matrix: instances[Int($0)].matrix,
                      state: instances[Int($0)].flags != .zero ? .hidden : .default
            )
        }

        guard let instancesBuffer = device.makeBuffer(bytes: &instanced, length: MemoryLayout<Instances>.stride * instanced.count) else {
            fatalError("💀 Unable to create instances buffer")
        }
        self.instancesBuffer = instancesBuffer
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

    /// Returns the 4x4 row-major transform matrix values associated with their respective instances.
    private var instanceTransforms: [float4x4] {
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
    }

    /// Builds the array of instances.
    public lazy var instances: [Instance] = {
        var instances = [Instance]()

        let instanceFlags: [Int16] = unsafeTypeArray(association: .instance, semantic: .flags)
        let instanceParents: [Int32] = unsafeTypeArray(association: .instance, semantic: .parent)
        let instanceMeshes: [Int32] = unsafeTypeArray(association: .instance, semantic: .mesh)
        let transforms = instanceTransforms

        // Build the base instances
        for (i, transform) in transforms.enumerated() {

            var flags: Int16 = 0
            if instanceFlags.indices.contains(i) {
                flags = instanceFlags[i]
            }

            let instance = Instance(index: i, matrix: transform, flags: flags)

            // Lookup the instance mesh
            let meshOffset = instanceMeshes[i]
            if meshOffset != .empty {
                instance.mesh = meshes[Int(meshOffset)]
            }

            // Calculate the bounding box of the instance async
            Task {
                instance.boundingBox = await calculateBoundingBox(instance)
            }
            instance.transparent = isTransparent(instance.mesh)
            instances.append(instance)
        }

        // Set the instance parent (if one)
        for (i, offset) in instanceParents.enumerated() {
            if offset != .empty {
                let parent = instances[Int(offset)]
                instances[i].parent = parent
            }
        }
        return instances
    }()

    /// Builds an array of instanced mesh structures (used for instancing).
    lazy var instancedMeshes: [InstancedMesh] = {
        var results = [InstancedMesh]()

        // Build a map of instances that share the same mesh
        var meshInstances = [Mesh: [UInt32]]()
        for instance in instances {
            guard let mesh = instance.mesh else { continue }
            if meshInstances[mesh] != nil {
                meshInstances[mesh]?.append(UInt32(instance.index))
             } else {
                 meshInstances[mesh] = [UInt32(instance.index)]
             }
        }

        for (mesh, instances) in meshInstances {
            let transparent = isTransparent(mesh)
            let meshInstances = InstancedMesh(mesh: mesh, transparent: transparent, instances: instances)
            results.append(meshInstances)
        }

        // Sort the meshes by opaques and transparents
        results.sort{ !$0.transparent && $1.transparent }

        // Set the base instance offsets
        var baseInstance: Int = 0
        for result in results {
            result.baseInstance = baseInstance
            baseInstance += result.instances.count
        }
        return results
    }()

    /// Returns the instance offsets (used for instancing). 
    lazy var instanceOffsets: [UInt32] = {
        return instancedMeshes.map { $0.instances }.reduce( [], + )
    }()

    /// Determines mesh transparency. This allows us to sort or
    /// split instances into opaque or transparent continuous ranges.
    /// - Parameters:
    ///   - mesh: the mesh to determine transparency value for
    /// - Returns: true if the mesh is transparent, otherwise false
    private func isTransparent(_ mesh: Mesh?) -> Bool {
        guard let mesh, let range = mesh.submeshes else { return true }

        // Find the lowest alpha value to determine transparency
        let alpha = range
            .map { submeshes[$0] }
            .sorted { $0.material?.rgba.w ?? .zero < $1.material?.rgba.w ?? .zero }
            .first?.material?.rgba.w ?? .zero
        return alpha < 1.0
    }

    /// Calculates the bounding box for the specified instance.
    /// - Parameters:
    ///   - instance: the instance to calculate the bounding box for
    /// - Returns: the axis aligned bounding box for the specified instance or nil if the instance has no mesh information.
    private func calculateBoundingBox(_ instance: Instance) async -> MDLAxisAlignedBoundingBox? {
        guard let vertices = vertices(for: instance) else { return nil }
        var minBounds: SIMD3<Float> = .zero
        var maxBounds: SIMD3<Float> = .zero
        for vertex in vertices {
            minBounds = min(minBounds, vertex)
            maxBounds = max(maxBounds, vertex)
        }
        return MDLAxisAlignedBoundingBox(maxBounds: maxBounds, minBounds: minBounds)
    }

    /// Helper method that returns all of the vertices that are contained in the specified instance.
    /// - Parameter instance: the instance to return all of the vertices for
    /// - Returns: all vertices contained in the specified instance
    func vertices(for instance: Instance) -> [SIMD3<Float>]? {
        guard let mesh = instance.mesh, let range = mesh.submeshes else { return nil }
        var results = [SIMD3<Float>]()
        let indexes = submeshes[range].map { indices[$0.indices].map { Int($0) * 3 } }.reduce( [], + )
        for i in indexes {
            let vertex: SIMD3<Float> = .init(positions[i..<(i+3)])
            results.append(vertex)
        }
        return results
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

    /// Convenience method for accessing attribute data into an array of the specified type.
    /// - Parameters:
    ///   - association: the aatribute descriptotor association to match against
    ///   - semantic: the aatribute descriptotor semantic to match against
    /// - Returns: the attribute data as an array of the specified type.
    fileprivate func unsafeTypeArray<T>(association: AttributeDescriptor.Association, semantic: AttributeDescriptor.Semantic) -> [T] {
        let attributes = attributes(association: association, semantic: semantic)
        return attributes.data.unsafeTypeArray()
    }
}

// MARK: Instance Mutation

extension Geometry {

    /// Toggles the instance hidden state to `.hidden` for all instances in the specified ids.
    /// - Parameters:
    ///   - ids: the ids of the instances to hide
    /// - Returns: the total count of hidden instances.
    public func hide(ids: [Int]) -> Int {
        guard let pointer: UnsafeMutablePointer<Instances> = instancesBuffer?.toUnsafeMutablePointer() else { return 0 }
        for id in ids {
            guard let index = instanceOffsets.firstIndex(of: UInt32(id)) else { continue }
            pointer.advanced(by: index).pointee.state = .hidden
        }
        return hiddenCount
    }

    /// Toggles the instance hidden state to `.selected` or
    /// - Parameters:
    ///   - id: the index of the instances to select or deselect
    /// - Returns: true if the instance was selected, otherwise false
    public func select(id: Int) -> Bool {
        guard let pointer: UnsafeMutablePointer<Instances> = instancesBuffer?.toUnsafeMutablePointer(),
              let index = instanceOffsets.firstIndex(of: UInt32(id)) else { return false }

        let instance = pointer[index]
        switch instance.state {
        case .default, .hidden:
            pointer.advanced(by: index).pointee.state = .selected
            return true
        case .selected:
            pointer.advanced(by: index).pointee.state = .default
            return false
        @unknown default:
            return false
        }
    }

    /// Unhides all hidden instances.
    public func unhide() {
        guard let pointer: UnsafeMutableBufferPointer<Instances> = instancesBuffer?.toUnsafeMutableBufferPointer() else { return }
        for (i, value) in pointer.enumerated() {
            if value.state == .hidden {
                pointer[i].state = .default
            }
        }
    }

    /// Convenience var that returns a count of the hidden instances.
    public var hiddenCount: Int {
        guard let pointer: UnsafeMutableBufferPointer<Instances> = instancesBuffer?.toUnsafeMutableBufferPointer() else { return 0 }
        return pointer[0..<pointer.count].filter{ $0.state == .hidden }.count
    }

    /// Convenience var that returns a count of the selected instances.
    public var selectedCount: Int {
        guard let pointer: UnsafeMutableBufferPointer<Instances> = instancesBuffer?.toUnsafeMutableBufferPointer() else { return 0 }
        return pointer[0..<pointer.count].filter{ $0.state == .selected }.count
    }
}
