//
//  MTLContext.swift
//  
//
//  Created by Kevin McKee
//

import MetalKit
import VimKitShaders

public class MTLContext {

    /// Convenience lazy var for the system default device.
    public static var device: MTLDevice = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("💀 Metal not supported")
        }
        return device
    }()

    /// Convenience lazy texture loader.
    public static var textureLoader: MTKTextureLoader = {
        MTKTextureLoader(device: device)
    }()

    /// Makes a library from the VImKitShaders library.
    public static func makeLibrary() -> MTLLibrary? {
        try? device.makeDefaultLibrary(bundle: Bundle.shaders())
    }

    /// Builds the vertex descriptor which informs Metal of the incoming buffer data
    public static func buildVertexDescriptor() -> MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()

        // Positions
        vertexDescriptor.attributes[.position].format = .float3
        vertexDescriptor.attributes[.position].bufferIndex = VertexAttribute.position.rawValue
        vertexDescriptor.attributes[.position].offset = 0

        // Normals
        vertexDescriptor.attributes[.normal].format = .float3
        vertexDescriptor.attributes[.normal].bufferIndex = VertexAttribute.normal.rawValue
        vertexDescriptor.attributes[.normal].offset = 0

        // Descriptor Layouts
        vertexDescriptor.layouts[.positions].stride = MemoryLayout<Float>.size * 3
        vertexDescriptor.layouts[.normals].stride = MemoryLayout<Float>.size * 3

        return vertexDescriptor
    }
}
