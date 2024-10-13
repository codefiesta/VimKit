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

    /// Convenience var for accessing the SHA 256 hash of this asset buffer.
    public lazy var sha256Hash: String = {
        bfast.sha256Hash
    }()

    /// Returns all of the asset names
    public lazy var names: [String] = {
        bfast.buffers.map { $0.name }
    }()

    /// The preview image extension.
    private let previewImageExtension: String = "png"

    /// The name of the default preview image file name.
    public lazy var previewImageName: String = {
        sha256Hash + "." + previewImageExtension
    }()

    /// Initializer
    init(_ bfast: BFast) {
        self.bfast = bfast
        extractPreviewImage()
    }

    /// Extracts the preview image from the last buffer as a .png image.
    private func extractPreviewImage() {
        guard let bufferName = names.last,
                let data = data(bufferName) else { return }

        let fileURL = FileManager.default.cacheDirectory.appendingPathComponent(previewImageName)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? data.write(to: fileURL)
        }
    }

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
