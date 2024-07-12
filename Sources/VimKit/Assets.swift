//
//  Assets.swift
//  
//
//  Created by Kevin McKee
//

import MetalKit

/// See: https://github.com/vimaec/vim/#assets-buffer
public class Assets {

    private let bfast: BFast

    /// Initializer
    init(_ bfast: BFast) {
        self.bfast = bfast
    }

    /// Returns all of the asset names
    public lazy var names: [String] = {
        return bfast.buffers.map { $0.name }
    }()

    /// Returns the raw data for the asset name
    public func data(_ name: String) -> Data? {
        guard let buffer = bfast.buffers.filter({ $0.name == name }).first else { return nil }
        return buffer.data
    }
}

extension Assets {

    /// Finds or creates a new Metal texture from the asset name
    public func texture(_ name: String) -> MTLTexture? {
        guard let data = data(name) else { return nil }
        let textureLoader = MTLContext.textureLoader
        return try? textureLoader.newTexture(data: data)
    }
}
