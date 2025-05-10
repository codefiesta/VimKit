//
//  Vim+Navigation.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Foundation
import MetalKit
import simd

// An extension that provides utilties for navigation.
extension Vim {

    /// Zooms to the nearest object that the camera is directly facing and  halving the distance between the camera and that object.
    /// - Parameters:
    ///   - out: a boolean to toggle zooming `in` or `out`
    @MainActor
    public func zoom(out: Bool = false) {
        guard let texture = delegate?.instancePickingTexture, let geometry else { return }
        let center = camera.viewportSize * 0.5

        let region = MTLRegionMake2D(Int(center.x), Int(center.y), 1, 1)
        let bytesPerRow = MemoryLayout<Int32>.stride * texture.width
        var pixelBytes: Int32 = .empty
        texture.getBytes(&pixelBytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        guard pixelBytes != .empty else { return }

        let id = Int(pixelBytes)
        guard let index = geometry.instanceOffsets.firstIndex(of: id) else { return }

        let query = camera.unprojectPoint(center)

        // Raycast into the instance
        guard let result = geometry.instances[index].raycast(geometry, query: query) else { return }
        let position = result.position

        // Calculate half the distance between our current camera position
        // and the nearest position of the object we are looking at
        let distance = distance(camera.position, position) * 0.5
        camera.zoom(to: position, distance: distance, out: out)
    }

    /// An enum that represents a look direction
    public enum Direction {
        case left
        case right
        case up
        case down
    }

    /// Points the camera in the specified direction from the current camera position.
    /// - Parameters:
    ///   - direction: the direction to look in
    @MainActor
    public func look(_ direction: Direction) {

        // The percentages we should multiply the screen coordinates by when looking in a direction
        let min: Float = 0.1
        let max: Float = 0.9

        // Our default focus position in screen coordinates
        var focus: SIMD2<Float> = camera.viewportSize * 0.5

        switch direction {
        case .left:
            focus.x = (camera.viewportSize * min).x
        case .right:
            focus.x = (camera.viewportSize * max).x
        case .up:
            focus.y = (camera.viewportSize * min).y
        case .down:
            focus.y = (camera.viewportSize * max).y
        }

        // Unproject the focus position and have the camera look in that direction
        let query = camera.unprojectPoint(focus)
        camera.look(in: query.direction)
    }

    /// Moves the camera in the specified direction from the current camera position.
    /// - Parameters:
    ///   - direction: the direction to move
    @MainActor
    public func pan(_ direction: Direction) {

        guard let geometry else { return }

        // TODO: This is a poor man's way of finding distance and look into doing something better
        let min: Float = 0.1
        let extents = geometry.bounds.extents

        // The percentages we should multiply the screen coordinates by when moving in a direction
        var translation: SIMD3<Float> = .zero

        switch direction {
        case .left:
            translation.x = extents.x * -min
        case .right:
            translation.x = extents.x * min
        case .up:
            translation.z = extents.y * min
        case .down:
            translation.z = extents.y * -min
        }
        camera.translate(translation: translation)
    }
}
