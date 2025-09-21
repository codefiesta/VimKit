//
//  Geometry.swift
//  VimKit
//
//  Created by Kevin McKee
//
import Combine
import Foundation
import MetalKit
import VimKitShaders
import struct SwiftUI.Color

// The MPS function name for computing the vertex normals on the GPU
private let computeVertexNormalsFunctionName = "computeVertexNormals"
// The MPS function name for computing the bounding boxes on the GPU
private let computeBoundingBoxesFunctionName = "computeBoundingBoxes"
// File extensions for mmap'd metal buffers
private let normalsBufferExtension = ".normals"
// The max number of color overrides to apply (4MB worth of colors)
private let maxColorOverrides = 256

/// See: https://github.com/vimaec/vim#geometry-buffer
/// This class was largely translated from VIM's CSharp + JS implementtions:
/// https://github.com/vimaec/g3d/blob/master/csharp/Vim.G3d/G3D.cs
/// https://github.com/vimaec/vim-ts/blob/develop/src/g3d.ts
public class Geometry: ObservableObject, @unchecked Sendable {

    /// Represents the state of our geometry buffer
    public enum State: Equatable, Sendable {
        case unknown
        case loading
        case indexing
        case ready
        case error(String)
    }

    /// Progress Reporting for loading the geometry data.
    @MainActor
    public dynamic let progress = Progress(totalUnitCount: 10)

    @MainActor @Published
    public var state: State = .unknown

    private var device: MTLDevice

    /// Boolean flag indicating if indirect command buffers are supported or not.
    private var supportsIndirectCommandBuffers: Bool {
        device.supportsFamily(.apple4)
    }

    /// Boolean flag indicating if the device supports non-uniform threadgroup sizes.
    private var supportsNonUniformThreadGroupSizes: Bool {
        device.supportsFamily(.apple4)
    }

    /// Returns the combined positions (vertex) buffer of all of the vertices for all the meshes layed out in slices of [x,y,z]
    public private(set) var positionsBuffer: MTLBuffer?
    /// Returns the combined index buffer of all of the indices.
    public private(set) var indexBuffer: MTLBuffer?
    /// Returns the combined buffer of all of the normals.
    public private(set) var normalsBuffer: MTLBuffer?
    /// Returns the combined buffer of all of the instance transforms and their state information.
    public private(set) var instancesBuffer: MTLBuffer?
    /// Returns the combined buffer of all of the instanced meshes..
    public private(set) var instancedMeshesBuffer: MTLBuffer?
    /// Returns the combined buffer of all of the materials.
    public private(set) var materialsBuffer: MTLBuffer?
    /// Returns the combined buffer of all of the submeshes.
    public private(set) var submeshesBuffer: MTLBuffer?
    /// Returns the combined buffer of all of the meshes.
    public private(set) var meshesBuffer: MTLBuffer?
    /// Returns the combinded buffer of all of the color overrides that can be applied to each instance.
    public private(set) var colorsBuffer: MTLBuffer?

    /// Return the model bounds.
    public var bounds: MDLAxisAlignedBoundingBox = .zero

    /// The Geometry Bounding Volume Hierarchy
    var bvh: BVH?

    /// The data container
    private let bfast: BFast
    private var attributes = [Attribute]()

    /// Cancellable tasks.
    var tasks = [Task<(), Never>]()

    /// Convenience var for accessing the SHA 256 hash of this geometry data.
    public lazy var sha256Hash: String = {
        bfast.sha256Hash
    }()

    /// Initializer
    init(_ bfast: BFast) {
        self.device = MTLContext.device
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
    }

    /// Cancels all running tasks.
    public func cancel() {
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
        publish(state: .unknown)
    }

    /// Asynchronously loads the geometry structures and Metal buffers.
    public func load() async {

        let start = Date.now
        defer {
            let timeInterval = abs(start.timeIntervalSinceNow)
            debugPrint("􀬨 Geometry loaded in [\(timeInterval.stringFromTimeInterval())]")
        }

        publish(state: .loading)

        // 1) Build the positions (vertex) buffer
        makePositionsBuffer()
        incrementProgressCount()

        // 2) Build the index buffer
        makeIndexBuffer()
        incrementProgressCount()

        // 3) Build the normals buffer
        await computeVertexNormals()
        incrementProgressCount()

        // 4) Build the materials buffer
        await makeMaterialsBuffer()
        incrementProgressCount()

        // 5) Build the submeshes buffer
        await makeSubmeshesBuffer()
        incrementProgressCount()

        // 6) Build the meshes buffer
        await makeMeshesBuffer()
        incrementProgressCount()

        // 7) Build the instances buffer
        await makeInstancesBuffer()
        incrementProgressCount()

        // 8) Compute the bounding boxes
        await computeBoundingBoxes()
        incrementProgressCount()

        // 9) Build the colors buffer
        await makeColorsBuffer()
        incrementProgressCount()

        // 10 Start indexing the file
        publish(state: .indexing)

        // Don't bother building the bvh tree if indirect command buffers are supported
        if !supportsIndirectCommandBuffers {
            await bvh = BVH(self)
        }
        incrementProgressCount()

        publish(state: .ready)
    }

    /// Publishes the geometry buffer state onto the main thread.
    /// - Parameter state: the new state to publish
    private func publish(state: State) {
        Task { @MainActor in
            self.state = state
        }
    }

    /// Increments the progress count by the specfied number of completed units on the main thread.
    /// - Parameter count: the number of units completed
    private func incrementProgressCount(_ count: Int64 = 1) {
        Task { @MainActor in
            self.progress.completedUnitCount += count
        }
    }

    // MARK: Postions (Vertex Buffer Raw Data)

    private func makePositionsBuffer() {
        let start = Date.now
        defer {
            let timeInterval = abs(start.timeIntervalSinceNow)
            debugPrint("􀬨 Positions [\(positions.count)] made in [\(timeInterval.stringFromTimeInterval())]")
        }

        let positions = attributes(association: .vertex, semantic: .position)
        guard let positionsBuffer = positions.makeBuffer(device: device, type: Float.self) else {
            fatalError("💀 Unable to create positions buffer")
        }
        self.positionsBuffer = positionsBuffer
    }

    /// Returns the combinded vertex buffer of all of the vertices for all the meshes layed out in slices of [x,y,z].
    public lazy var positions: UnsafeMutableBufferPointer<Float> = {
        assert(positionsBuffer != nil, "💩 Misuse [positions]")
        return positionsBuffer!.toUnsafeMutableBufferPointer()
    }()

    // MARK: Index Buffer

    private func makeIndexBuffer() {
        let start = Date.now
        defer {
            let timeInterval = abs(start.timeIntervalSinceNow)
            debugPrint("􀬨 Indices [\(indices.count)] made in [\(timeInterval.stringFromTimeInterval())]")
        }
        let indices = attributes(association: .corner, semantic: .index)

        guard let indexBuffer = indices.makeBuffer(device: device, type: UInt32.self) else {
            fatalError("💀 Unable to create index buffer")
        }
        self.indexBuffer = indexBuffer
    }

    /// Returns the combined index buffer of all the meshes (one index per corner, and per half-edge).
    /// The values in this index buffer are relative to the beginning of the vertex buffer.
    public lazy var indices: UnsafeMutableBufferPointer<UInt32> = {
        assert(indexBuffer != nil, "💩 Misuse [indices]")
        return indexBuffer!.toUnsafeMutableBufferPointer()
    }()

    /// Provides a buffered pointer to the color overrides.
    public lazy var colors: UnsafeMutableBufferPointer<SIMD4<Float>> = {
        assert(colorsBuffer != nil, "💩 Misuse [colors]")
        return colorsBuffer!.toUnsafeMutableBufferPointer()
    }()

    /// Calculates the vertex normals.
    /// TODO: Port this over to Metal Performance Shaders to perform this work on the GPU.
    /// - https://computergraphics.stackexchange.com/questions/4031/programmatically-generating-vertex-normals
    /// -  https://iquilezles.org/articles/normals/
    /// - Returns: an array of vertex normals
    @available(*, deprecated, message: "Use computeVertexNormals(device:cacheDirectory).")
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
    @available(*, deprecated, message: "Use computeVertexNormals(device:cacheDirectory) to build vertex normals.")
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
            let vertices = positions.chunked(into: 3).map { SIMD3<Float>($0) }
            for i in stride(from: 0, to: indices.count, by: 3) {
                let a = vertices[Int(indices[i])]
                let b = vertices[Int(indices[i+1])]
                let c = vertices[Int(indices[i+2])]
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

    /// Makes the meshes buffer.
    private func makeMeshesBuffer() async {
        guard !Task.isCancelled else { return }
        let start = Date.now
        defer {
            let timeInterval = abs(start.timeIntervalSinceNow)
            debugPrint("􀬨 Meshes [\(meshes.count)] made in [\(timeInterval.stringFromTimeInterval())]")
        }

        let meshSubmeshOffsets: [Int32] = unsafeTypeArray(association: .mesh, semantic: .submeshoffset)
        var meshes = [Mesh]()

        for (i, offset) in meshSubmeshOffsets.enumerated() {

            // Calculate the range of submeshes contained inside this mesh
            let start = Int(offset)
            let nextOffset = i < meshSubmeshOffsets.endIndex - 1 ? meshSubmeshOffsets[Int(i+1)] : meshSubmeshOffsets.last!
            let end = i < meshSubmeshOffsets.endIndex - 1 ? Int(nextOffset): Int(meshSubmeshOffsets.last!)
            let range: Range<Int> = start..<end

            // Build the mesh
            let mesh = Mesh(range)
            meshes.append(mesh)
        }

        self.meshesBuffer = device.makeBuffer(bytes: &meshes, length: MemoryLayout<Mesh>.stride * meshes.count, options: [.storageModeShared])
    }

    /// Provides a buffered pointer to the meshes.
    public lazy var meshes: UnsafeMutableBufferPointer<Mesh> = {
        assert(meshesBuffer != nil, "💩 Misuse [meshes]")
        return meshesBuffer!.toUnsafeMutableBufferPointer()
    }()

    // MARK: Submeshes

    private func makeSubmeshesBuffer() async {
        guard !Task.isCancelled else { return }

        let start = Date.now
        defer {
            let timeInterval = abs(start.timeIntervalSinceNow)
            debugPrint("􀬨 Submeshes [\(submeshes.count)] made in [\(timeInterval.stringFromTimeInterval())]")
        }

        let submeshIndexOffsets: [Int32] = unsafeTypeArray(association: .submesh, semantic: .indexoffset)
        let submeshMaterials: [Int32] = unsafeTypeArray(association: .submesh, semantic: .material)

        var submeshes = [Submesh]()

        for (i, offset) in submeshIndexOffsets.enumerated() {

            // Calculate the range of values in the index buffer
            let start = Int(offset)
            let nextOffset = i < submeshIndexOffsets.endIndex - 1 ? submeshIndexOffsets[Int(i+1)] : submeshIndexOffsets.last!
            let end = i < submeshIndexOffsets.endIndex - 1 ? Int(nextOffset): Int(submeshIndexOffsets.last!)
            let range: Range<Int> = start..<end

            // Account for a submesh with an empty material
            let material = submeshMaterials[i] == .empty ? Int32(defaultMaterial): submeshMaterials[i]
            let submesh = Submesh(material, range)
            submeshes.append(submesh)
        }

        self.submeshesBuffer = device.makeBuffer(bytes: &submeshes, length: MemoryLayout<Submesh>.stride * submeshes.count, options: [.storageModeShared])
    }

    /// Provides a buffered pointer to the submeshes.
    public lazy var submeshes: UnsafeMutableBufferPointer<Submesh> = {
        assert(submeshesBuffer != nil, "💩 Misuse [submeshes]")
        return submeshesBuffer!.toUnsafeMutableBufferPointer()
    }()

    // MARK: Instances

    /// Returns the 4x4 row-major transform matrix values associated with their respective instances.
    private func instanceTransforms() -> [float4x4] {
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

    /// Holds a hash of mesh indexes and an array of instance indexes that share the mesh.
    private(set) var meshInstances = [Int: [Int]]()

    /// Provides a hash lookup of instance indices into their respective instanced meshes index.
    /// The key is the instance index and the value is the index into the `instancedMeshes` array.
    private(set) var instancedMeshesMap = [Int: Int]()

    /// Returns the instance offsets (used for instancing).
    private(set) var instanceOffsets = [Int]()

    /// Holds a set of hidden instanced meshes.
    private(set) var hiddeninstancedMeshes = Set<Int>()

    /// Makes the instance buffer.
    private func makeInstancesBuffer() async {

        guard !Task.isCancelled else { return }

        let start = Date.now
        defer {
            let timeInterval = abs(start.timeIntervalSinceNow)
            debugPrint("􀬨 Instances [\(instances.count)] made in [\(timeInterval.stringFromTimeInterval())]")
        }

        var instances = [Instance]()
        let instanceFlags: [Int16] = unsafeTypeArray(association: .instance, semantic: .flags)
        let instanceParents: [Int32] = unsafeTypeArray(association: .instance, semantic: .parent)
        let instanceMeshes: [Int32] = unsafeTypeArray(association: .instance, semantic: .mesh)
        let transforms = instanceTransforms()

        // 1) Build the array of instances
        for (i, transform) in transforms.enumerated() {

            var flags: Int16 = 0
            if instanceFlags.indices.contains(i) {
                flags = instanceFlags[i]
            }

            let mesh = Int(instanceMeshes[i])
            let parent = Int(instanceParents[i])
            let transparent = isTransparent(mesh)
            let instance = Instance(index: i, matrix: transform, flags: flags, parent: parent, mesh: mesh, transparent: transparent)

            // Drop any instances that don't have empty mesh data or are hidden by default
            guard mesh != .empty, flags == .zero else { continue }

            // Add this instance to the mesh map
            if meshInstances[mesh] != nil {
                meshInstances[mesh]?.append(i)
            } else {
                meshInstances[mesh] = [i]
            }
            instances.append(instance)
        }

        // 2) Sort the instances by transparency & mesh index
        instances.sort {
            ($0.transparent ? 0 : 1, $0.mesh) > ($1.transparent ? 0 : 1, $1.mesh)
        }

        // 3) Make the array of instancedMeshes
        var instancedMeshes = [InstancedMesh]()
        var currentMesh = -1
        for (i, instance) in instances.enumerated() {

            let mesh = instance.mesh

            // Map the offset
            instanceOffsets.append(instance.index)

            // If we have a new mesh, insert it into the array
            if currentMesh != mesh {

                // Build a new instanced mesh
                let transparent = isTransparent(mesh)
                let instanceCount = meshInstances[mesh]?.count ?? 0
                let instanced = InstancedMesh(mesh: mesh, transparent: transparent, instanceCount: instanceCount, baseInstance: i)
                instancedMeshes.append(instanced)
                currentMesh = mesh
            }

            // Map the instance to it's instanced mesh group
            instancedMeshesMap[i] = instancedMeshes.indices.last
        }

        // 4) Make the instances buffer
        self.instancesBuffer = device.makeBuffer(bytes: &instances, length: MemoryLayout<Instance>.stride * instances.count, options: [.storageModeShared])

        // 5) Make the instanced meshes buffer
        self.instancedMeshesBuffer = device.makeBuffer(bytes: &instancedMeshes, length: MemoryLayout<InstancedMesh>.stride * instancedMeshes.count, options: [.storageModeShared])
    }

    /// Provides a buffered pointer to the instances.
    public lazy var instances: UnsafeMutableBufferPointer<Instance> = {
        assert(instancesBuffer != nil, "💩 Misuse [instances]")
        return instancesBuffer!.toUnsafeMutableBufferPointer()
    }()

    /// Provides a buffered pointer to the instanced meshes.
    public lazy var instancedMeshes: UnsafeMutableBufferPointer<InstancedMesh> = {
        assert(instancedMeshesBuffer != nil, "💩 Misuse [instancedMeshes]")
        return instancedMeshesBuffer!.toUnsafeMutableBufferPointer()
    }()

    /// Calculates the max grid width by determining the max number of submeshes a mesh could possibly contain.
    private lazy var gridWidth: Int = {
        meshes.map { $0.submeshes.count }.max() ?? 1
    }()

    /// Calculates the max grid width of the opaque meshes by determining the max number of submeshes a mesh could possibly contain.
    public lazy var gridWidthOpaques: Int = {
        let opaqueMeshes = instancedMeshes.filter { !$0.transparent }.map { $0.mesh }.map { meshes[$0] }
        return opaqueMeshes.map { $0.submeshes.count }.max() ?? 1
    }()

    /// Calculates the max grid width of the transparent meshes by determining the max number of submeshes a mesh could possibly contain.
    public lazy var gridWidthTransparents: Int = {
        let transparentMeshes = instancedMeshes.filter { $0.transparent }.map { $0.mesh }.map { meshes[$0] }
        return transparentMeshes.map { $0.submeshes.count }.max() ?? 1
    }()

    /// Provides a grid size for executing indirect command buffer commands.
    /// The width is the maximum number of submeshes a mesh could contain.
    /// The height is the number of instanced meshes.
    public lazy var gridSize: MTLSize = {
        .init(width: gridWidth, height: instancedMeshes.count, depth: 1)
    }()

    /// Provides a grid size for executing indirect command buffer commands on opaque instanced meshes.
    /// The width is the maximum number of submeshes a mesh could contain.
    /// The height is the number of opaque instanced meshes.
    public lazy var gridSizeOpaques: MTLSize = {
        .init(width: gridWidthOpaques, height: instancedMeshOpaquesCount, depth: 1)
    }()

    /// Provides a grid size for executing indirect command buffer commands on transparent instanced meshes.
    /// The width is the maximum number of submeshes a mesh could contain.
    /// The height is the number of transparent instanced meshes.
    public lazy var gridSizeTransparents: MTLSize = {
        .init(width: gridWidthTransparents, height: instancedMeshTransparentsCount, depth: 1)
    }()

    /// Provides a count of opaque instanced meshes.
    public lazy var instancedMeshOpaquesCount: Int = {
        instancedMeshes.filter { $0.transparent == false }.count
    }()

    /// Provides a count of transparent instanced meshes.
    public lazy var instancedMeshTransparentsCount: Int = {
        instancedMeshes.filter { $0.transparent == true }.count
    }()

    /// Provides the offset into instanced meshes where the transparent instanced meshes begin.
    /// This vale can be used as the buffer offset by multiplying with `MemoryLayout<InstancedMesh>.size`.
    public lazy var instancedMeshTransparentsOffset: Int = {
        instancedMeshes.firstIndex { $0.transparent == true } ?? .zero
    }()

    // MARK: Materials

    /// Makes the materials buffer.
    private func makeMaterialsBuffer() async {
        guard !Task.isCancelled else { return }

        let start = Date.now
        defer {
            let timeInterval = abs(start.timeIntervalSinceNow)
            debugPrint("􀬨 Materials [\(materials.count)] made in [\(timeInterval.stringFromTimeInterval())]")
        }

        let colors: [Float] = unsafeTypeArray(association: .material, semantic: .color)
        let materialColors: [SIMD4<Float>] = colors.chunked(into: 4).map { SIMD4<Float>($0) }
        let materialGlossiness: [Float] = unsafeTypeArray(association: .material, semantic: .glossiness)
        let materialSmoothness: [Float] = unsafeTypeArray(association: .material, semantic: .smoothness)

        var materials = [Material]()
        for (i, color) in materialColors.enumerated() {
            let glossiness = materialGlossiness[i]
            let smoothness = materialSmoothness[i]
            let material = Material(glossiness: glossiness, smoothness: smoothness, rgba: color)
            materials.append(material)
        }

        self.materialsBuffer = device.makeBuffer(
            bytes: &materials,
            length: MemoryLayout<Material>.stride * materials.count,
            options: [.storageModeShared]
        )
    }

    /// Provides a buffered pointer to the materials.
    public lazy var materials: UnsafeMutableBufferPointer<Material> = {
        assert(materialsBuffer != nil, "💩 Misuse [materials]")
        return materialsBuffer!.toUnsafeMutableBufferPointer()
    }()

    /// Provides the default material for submeshes that have no material specified.
    /// Even though the spec says all submeshes have a material, this is not true.
    public lazy var defaultMaterial: Int = {
        materials.firstIndex { material in
            material.rgba == .one
        } ?? .zero
    }()
}

// MARK: Helpers + Utilities

extension Geometry {

    /// Determines mesh transparency. This allows us to sort or
    /// split instances into opaque or transparent continuous ranges.
    /// - Parameters:
    ///   - mesh: the mesh to determine transparency value for
    /// - Returns: true if the mesh is transparent, otherwise false
    private func isTransparent(_ index: Int) -> Bool {

        guard index != .empty else { return true }
        let mesh = meshes[index]

        let range = mesh.submeshes.range
        let submeshe = submeshes[range].filter{ $0.material != .empty }
        let alphas = submeshe.map { materials[$0.material].rgba.w }.sorted { $0 < $1 }
        guard alphas.isNotEmpty else { return true }
        return alphas[0] < 1.0

    }

    /// Computes the vertiex normals on the GPU using Metal Performance Shaders.
    private func computeVertexNormals() async {

        let start = Date.now
        defer {
            let timeInterval = abs(start.timeIntervalSinceNow)
            debugPrint("􀬨 Normals computed in [\(timeInterval.stringFromTimeInterval())]")
        }

        // If the normals file has already been generated, just make the MTLBuffer from it
        let cacheDirectory = FileManager.default.cacheDirectory
        let normalsBufferFile = cacheDirectory.appending(path: "\(sha256Hash)\(normalsBufferExtension)")
        if FileManager.default.fileExists(atPath: normalsBufferFile.path) {
            guard let normalsBuffer = device.makeBufferNoCopy(normalsBufferFile, type: Float.self) else {
                fatalError("💀 Unable to make MTLBuffer from normals file.")
            }
            self.normalsBuffer = normalsBuffer
            return
        }

        let commandQueue = device.makeCommandQueue()
        var positionsCount = positions.count
        var indicesCount = indices.count

        guard !Task.isCancelled,
              let library = MTLContext.makeLibrary(),
              let function = library.makeFunction(name: computeVertexNormalsFunctionName),
              let pipelineState = try? await device.makeComputePipelineState(function: function),
              let positionsBuffer,
              let indexBuffer,
              let faceNormalsBuffer = device.makeBuffer(
                length: MemoryLayout<SIMD3<Float>>.stride * (positionsCount/3),
                options: [.storageModeShared]),
              let resultsBuffer = device.makeBuffer(
                length: MemoryLayout<Float>.stride * positionsCount,
                options: [.storageModeShared]),
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            debugPrint("💩 Unable to compute normals.")
            return
        }

        computeEncoder.setComputePipelineState(pipelineState)

        // Encode the buffers to pass to the GPU
        computeEncoder.setBuffer(positionsBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(indexBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(faceNormalsBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(resultsBuffer, offset: 0, index: 3)
        computeEncoder.setBytes(&positionsCount, length: MemoryLayout<Int>.size, index: 4)
        computeEncoder.setBytes(&indicesCount, length: MemoryLayout<Int>.size, index: 5)

        // Set the thread group size and dispatch
        let gridSize: MTLSize = .init(width: 1, height: 1, depth: 1)
        let width = pipelineState.threadExecutionWidth
        let height = pipelineState.maxTotalThreadsPerThreadgroup / width
        let threadsPerThreadgroup: MTLSize = .init(width: width, height: height, depth: 1)

        if supportsNonUniformThreadGroupSizes {
            computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerThreadgroup)
        } else {
            computeEncoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadsPerThreadgroup)
        }

        computeEncoder.endEncoding()
        commandBuffer.commit()
        await commandBuffer.completed()

        // Finally, write the results to a cache file and create the MTLBuffer from it
        let data = Data(bytes: resultsBuffer.contents(), count: resultsBuffer.length)
        try? data.write(to: normalsBufferFile)
        guard let normalsBuffer = device.makeBufferNoCopy(normalsBufferFile, type: Float.self) else {
            fatalError("💀 Unable to make MTLBuffer from normals file.")
        }
        self.normalsBuffer = normalsBuffer
    }

    /// Computes all of the instance bounding boxes on the GPU via Metal Performance Shaders.
    private func computeBoundingBoxes() async {
        let start = Date.now
        defer {
            let timeInterval = abs(start.timeIntervalSinceNow)
            debugPrint("􀬨 Bounding boxes computed in [\(timeInterval.stringFromTimeInterval())]")
        }

        let commandQueue = device.makeCommandQueue()
        let instanceCount = instances.count - 1

        guard !Task.isCancelled,
              let library = MTLContext.makeLibrary(),
              let function = library.makeFunction(name: computeBoundingBoxesFunctionName),
              let pipelineState = try? await device.makeComputePipelineState(function: function),
              let positionsBuffer, let indexBuffer, let instancesBuffer, let meshesBuffer, let submeshesBuffer,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            debugPrint("💩 Unable to compute bounding boxes.")
            return
        }

        computeEncoder.setComputePipelineState(pipelineState)

        // Encode the buffers to pass to the GPU
        computeEncoder.setBuffer(positionsBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(indexBuffer, offset: 0, index: 1)
        computeEncoder.setBuffer(instancesBuffer, offset: 0, index: 2)
        computeEncoder.setBuffer(meshesBuffer, offset: 0, index: 3)
        computeEncoder.setBuffer(submeshesBuffer, offset: 0, index: 4)

        // Set the thread group size and dispatch
        let gridSize: MTLSize = .init(width: instanceCount, height: 1, depth: 1)
        let width = pipelineState.threadExecutionWidth
        let height = pipelineState.maxTotalThreadsPerThreadgroup / width
        let threadsPerThreadgroup: MTLSize = .init(width: width, height: height, depth: 1)

        if supportsNonUniformThreadGroupSizes {
            computeEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerThreadgroup)
        } else {
            computeEncoder.dispatchThreadgroups(gridSize, threadsPerThreadgroup: threadsPerThreadgroup)
        }

        computeEncoder.endEncoding()
        commandBuffer.commit()
        await commandBuffer.completed()

        // For now, just loop through the instances on the CPU to calculate the world bounds
        // In the future we could do this on the GPU but juice really isn't worth the squeeze
        var minMounds: SIMD3<Float> = .zero
        var maxMounds: SIMD3<Float> = .zero
        for instance in instances {
            minMounds = min(instance.boundingBox.minBounds, minMounds)
            maxMounds = max(instance.boundingBox.maxBounds, maxMounds)
        }
        bounds = .init(maxBounds: maxMounds, minBounds: minMounds)
    }

    /// Calculates the bounding box for the specified instance.
    /// - Parameters:
    ///   - instance: the instance to calculate the bounding box for
    /// - Returns: the axis aligned bounding box for the specified instance or nil if the instance has no mesh information.
    @available(*, deprecated, message: "Use computeBoundingBoxes(device:cacheDirectory).")
    func calculateBoundingBox(_ instance: Instance) -> MDLAxisAlignedBoundingBox? {
        guard !Task.isCancelled, let vertices = vertices(for: instance), vertices.isNotEmpty else { return nil }
        let matrix = instance.matrix
        let point: SIMD4<Float> = .init(vertices[0], 1.0)
        let worldPoint = matrix * point
        var minBounds = worldPoint.xyz
        var maxBounds = worldPoint.xyz
        for vertex in vertices {
            let point: SIMD4<Float> = .init(vertex, 1.0)
            let worldPoint = matrix * point
            minBounds = min(minBounds, worldPoint.xyz)
            maxBounds = max(maxBounds, worldPoint.xyz)
        }
        return MDLAxisAlignedBoundingBox(maxBounds: maxBounds, minBounds: minBounds)
    }

    /// Helper method to retrieve the vertex at the specified index.
    /// - Parameter index: the indices index
    /// - Returns: the vertex at the specified index
    func vertex(at index: Int) -> SIMD3<Float> {
        let i = Int(indices[index] * 3)
        return .init(positions[i..<(i+3)])
    }

    /// Helper method that returns a face for the specifed indices.
    /// - Parameter indices: the face indices
    /// - Returns: a face for the specified indices
    func face(for indices: SIMD3<Int>) -> Face {
        let a = vertex(at: indices.x)
        let b = vertex(at: indices.y)
        let c = vertex(at: indices.z)
        return Face(a: a, b: b, c: c)
    }

    /// Helper method that returns all of the vertices that are contained in the specified instance.
    /// - Parameter instance: the instance to return all of the vertices for
    /// - Returns: all vertices contained in the specified instance
    func vertices(for instance: Instance) -> [SIMD3<Float>]? {
        guard instance.mesh != .empty else { return nil }
        let mesh = meshes[instance.mesh]
        let range = mesh.submeshes.range
        var results = [SIMD3<Float>]()
        let indexes = submeshes[range].map { indices[$0.indices].map { Int($0) * 3} }.reduce( [], + )
        for i in indexes {
            let vertex: SIMD3<Float> = .init(positions[i..<(i+3)])
            results.append(vertex)
        }
        return results
    }

    /// Helper method that returns all of the faces that are contained in the specified instance.
    /// - Parameter instance: the instance to return all of the faces for
    /// - Returns: all faces contained in the specified instance
    func faces(for instance: Instance) -> [Face]? {
        guard let vertices = vertices(for: instance)?.chunked(into: 3), vertices.isNotEmpty else { return nil }
        var results = [Face]()
        for vertex in vertices {
            results.append(Face(a: vertex[0], b: vertex[1], c: vertex[2]))
        }
        return results
    }

    /// Finds the attributes that have the specified association and semantic.
    /// - Parameters:
    ///   - association: the aatribute descriptotor association to match against
    ///   - semantic: the aatribute descriptotor semantic to match against
    /// - Returns: all attributes that match the soecified association and semantic
    private func attributes(association: AttributeDescriptor.Association, semantic: AttributeDescriptor.Semantic) -> [Attribute] {
        attributes.filter { $0.descriptor.association == association && $0.descriptor.semantic == semantic }
    }

    /// Convenience method for accessing attribute data into an array of the specified type.
    /// - Parameters:
    ///   - association: the aatribute descriptotor association to match against
    ///   - semantic: the aatribute descriptotor semantic to match against
    /// - Returns: the attribute data as an array of the specified type.
    private func unsafeTypeArray<T>(association: AttributeDescriptor.Association, semantic: AttributeDescriptor.Semantic) -> [T] {
        let attributes = attributes(association: association, semantic: semantic)
        return attributes.data.unsafeTypeArray()
    }
}

// MARK: Instance State
extension Geometry {

    /// Toggles all instances states from the `from` state to the `to` state.
    /// - Parameters:
    ///   - from: the instance state to match
    ///   - to: the iinstance state to switch to
    public func toggle(from: InstanceState, to: InstanceState) {
        for (i, value) in instances.enumerated() {
            if value.state == from {
                instances[i].state = to
            }
        }
    }

    /// Convenience func that returns a count of the instances in the specified state.
    /// - Parameter state: the state to match
    public func count(state: InstanceState) -> Int {
        instances.filter{ $0.state == state }.count
    }
}


// MARK: Instance Hiding

extension Geometry {

    /// Toggles the instance hidden state to `.hidden` for all instances in the specified ids.
    /// - Parameters:
    ///   - ids: the ids of the instances to hide
    /// - Returns: the total count of hidden instances.
    public func hide(ids: Set<Int>) -> Int {
        for id in ids {
            guard let index = instanceOffsets.firstIndex(of: id) else { continue }
            instances[index].state = .hidden
        }

        let hidden = instances.filter{ $0.state == .hidden }.map { Int($0.index) }
        let hiddenSet = Set<Int>(hidden)

        // Hide all of the instanced meshes where all shared instances are hidden
        for (i, instanced) in instancedMeshes.enumerated() {
            let instancesSet = Set<Int>(meshInstances[instanced.mesh] ?? [])
            if instancesSet.isSubset(of: hiddenSet) {
                hiddeninstancedMeshes.insert(i)
            }
        }
        return hidden.count
    }

    /// Toggles all instance
    /// - Parameters:
    ///   - ids: the ids of the instances not to hide
    public func hide(excluding: Set<Int>) {
        let excluded = excluding.compactMap{ instanceOffsets.firstIndex(of: $0) }

        for (i, _) in instances.enumerated() {
            if excluded.contains(i) {
                instances[i].state = .default
            } else {
                instances[i].state = .hidden
            }
        }
    }

    /// Unhides all hidden instances.
    public func unhide() {
        for (i, value) in instances.enumerated() {
            if value.state == .hidden {
                instances[i].state = .default
            }
        }
        hiddeninstancedMeshes.removeAll()
    }
}

// MARK: Instance Selection

extension Geometry {

    /// Returns the instance with the specified id.
    /// - Parameter id: the instance id
    /// - Returns: the instance with the specified id or nil
    public func instance(id: Int) -> Instance? {
        guard let index = instanceOffsets.firstIndex(of: id) else { return nil }
        return instances[index]
    }

    /// Toggles the instance hidden state to `.selected` or
    /// - Parameters:
    ///   - id: the index of the instances to select or deselect
    /// - Returns: true if the instance was selected, otherwise false
    public func select(id: Int) -> Bool {
        guard let index = instanceOffsets.firstIndex(of: id) else { return false }
        let instance = instances[index]
        switch instance.state {
        case .default, .hidden, .isolated:
            instances[index].state = .selected
            return true
        case .selected:
            instances[index].state = .default
            return false
        @unknown default:
            return false
        }
    }
}

// MARK: Instance Isolation

extension Geometry {

    public func isolate(ids: Set<Int>) {
        for (i, value) in instances.enumerated() {
            instances[i].state = ids.contains(value.index) ? .isolated : .hidden
        }
    }
}

// MARK: Instance Color Overrides

extension Geometry {

    /// Makes the color overrides buffer
    private func makeColorsBuffer() async {
        guard !Task.isCancelled else { return }

        let start = Date.now
        defer {
            let timeInterval = abs(start.timeIntervalSinceNow)
            debugPrint("􀬨 Colors [\(colors.count)] made in [\(timeInterval.stringFromTimeInterval())]")
        }

        var colors = [SIMD4<Float>](repeating: .zero, count: maxColorOverrides)

        // Set the first color override as the selection color
        colors[0] = Color.objectSelectionColor.channels
        self.colorsBuffer = device.makeBuffer(
            bytes: &colors,
            length: MemoryLayout<SIMD4<Float>>.stride * colors.count, options: [.storageModeShared])
    }

    /// Applies the color override to all instances in the specified ids.
    ///
    /// This example shows how to use the `setColor(ids:color:)`.
    ///
    ///     let ids = [0, 1, 2]
    ///     let color = Color.red.channels
    ///     geometry.setColor(ids: ids, color: color)
    ///
    /// - Parameters:
    ///   - color: the override color to apply
    ///   - ids: the ids of the instances to apply this color override for
    public func apply(color: SIMD4<Float>, to ids: Set<Int>) {

        // Find the index of the color if it's already in the colors buffer
        var colorIndex: Int = 0
        if let index = colors.firstIndex(of: color) {
            // Use the index of the found color
            colorIndex = index
        } else if let index = colors.firstIndex(of: .zero) {
            // Push the color into the first empty slot
            colors[index] = color
            colorIndex = index
        } else {
            // No empty color slots
            return
        }

        // Update the instances buffer with the color override index
        for id in ids {
            guard let index = instanceOffsets.firstIndex(of: id) else { continue }
            instances[index].colorIndex = colorIndex
        }
    }

    /// Unapplies the color override to all instances in the specified ids
    /// - Parameter ids: the ids of the instances to apply this color override for
    public func unapply(ids: Set<Int>) {
        var erasables = Set<Int>() // Collect the erasable color indices
        for id in ids {
            guard let index = instanceOffsets.firstIndex(of: id) else { continue }
            let instance = instances[index]
            if instance.colorIndex != .empty {
                erasables.insert(instance.colorIndex)
            }
            instances[index].colorIndex = .empty
        }

        // Check no other instances have a reference to the same color override
        for (_, value) in instances.enumerated() {
            let index = value.colorIndex
            if erasables.contains(index) {
                erasables.remove(index)
            }
        }

        // Finally, erase any unused color overrides
        for i in erasables {
            colors[i] = .zero
        }
    }

    /// Removes all color overrides.
    public func unapplyAll() {
        // Erase all of the color indices from the instances
        for (i, _) in instances.enumerated() {
            instances[i].colorIndex = .empty
        }

        for (i, _) in colors.enumerated() {
            if i > 0 {
                colors[i] = .zero
            }
        }
    }
}
