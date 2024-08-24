//
//  MDLAxisAlignedBoundingBox+Extensions.swift
//
//
//  Created by Kevin McKee
//

import ModelIO
import Spatial

extension MDLAxisAlignedBoundingBox {

    /// Returns the center point of the box.
    var center: SIMD3<Float> {
        (maxBounds + minBounds) * .half
    }

    /// Returns the 8 corner points of the bounding box.
    var corners: [SIMD3<Float>] {
        return [
            minBounds,
            [minBounds.x, minBounds.y, maxBounds.z],
            [minBounds.x, maxBounds.y, minBounds.z],
            [minBounds.x, maxBounds.y, maxBounds.z],
            [maxBounds.x, minBounds.y, minBounds.z],
            [maxBounds.x, minBounds.y, maxBounds.z],
            [maxBounds.x, maxBounds.y, minBounds.z],
            maxBounds
        ]
    }

    /// Returns the longest edge of the bounding box.
    var longestEdge: Float {
        let distance = maxBounds - minBounds
        return max(distance.x, max(distance.y, distance.z))
    }

    /// Returns the box positive extents.
    var extents: SIMD3<Float> {
        maxBounds - center
    }

    /// Returns the radius of the box from the center to it's max bounds.
    var radius: Float {
        distance(center, maxBounds)
    }

    /// Determines and returns the longest axis of the bounding box.
    var longestAxis: Axis3D {

        var axis: Axis3D = .x

        let lengths: SIMD3<Float> = [
            abs(maxBounds.x - minBounds.x),
            abs(maxBounds.y - minBounds.y),
            abs(maxBounds.z - minBounds.z)
        ]

        if lengths.y > lengths.x, lengths.y > lengths.z {
            axis = .y
        } else if lengths.z > lengths.x, lengths.z > lengths.y {
            axis = .z
        }
        return axis
    }

    /// Initializes the bounding box from an arry of points
    /// - Parameter points: the points
    init(points: [SIMD3<Float>]) {
        assert(points.count > 0)
        var maxBounds: SIMD3<Float> = .zero
        var minBounds: SIMD3<Float> = .zero
        for point in points {
            minBounds.x = min(minBounds.x, point.x)
            minBounds.y = min(minBounds.x, point.y)
            minBounds.z = min(minBounds.x, point.z)
            maxBounds.x = min(maxBounds.x, point.x)
            maxBounds.y = min(maxBounds.x, point.y)
            maxBounds.z = min(maxBounds.x, point.z)
        }
        self.init(maxBounds: maxBounds, minBounds: minBounds)
    }

    /// Produces a union of all the provided boxes, setting the max bounds of this box to the  max of all the
    /// boxes' max bounds and the min bounds of this box to the lesser of the boxes' lower bounds.
    /// - Parameters:
    ///     - boxes: the array of bounding boxes to contain
    init(containing boxes: [MDLAxisAlignedBoundingBox]) {

        var maxBounds: SIMD3<Float> = .zero
        var minBounds: SIMD3<Float> = .zero

        for box in boxes {
            minBounds.x = min(minBounds.x, box.minBounds.x)
            minBounds.y = min(minBounds.y, box.minBounds.y)
            minBounds.z = min(minBounds.z, box.minBounds.z)

            maxBounds.x = max(maxBounds.x, box.maxBounds.x)
            maxBounds.y = max(maxBounds.y, box.maxBounds.y)
            maxBounds.z = max(maxBounds.z, box.maxBounds.z)
        }
        self.init(maxBounds: maxBounds, minBounds: minBounds)
    }

    /// Produces a union of this box and the other box.
    /// - Parameter other: the box that will be unioned with this box
    /// - Returns: a newly unioned box of this and the other box.
    func union(_ other: MDLAxisAlignedBoundingBox) -> MDLAxisAlignedBoundingBox {

        var maxBounds: SIMD3<Float> = .zero
        var minBounds: SIMD3<Float> = .zero

        minBounds.x = min(minBounds.x, other.minBounds.x)
        minBounds.y = min(minBounds.y, other.minBounds.y)
        minBounds.z = min(minBounds.z, other.minBounds.z)

        maxBounds.x = max(maxBounds.x, other.maxBounds.x)
        maxBounds.y = max(maxBounds.y, other.maxBounds.y)
        maxBounds.z = max(maxBounds.z, other.maxBounds.z)
        return .init(maxBounds: maxBounds, minBounds: minBounds)
    }

    /// Returns true if the specified point is contained inside this bounding box.
    /// - Parameter point: the point the check
    /// - Returns: true if the point is inside the bounding box
    func contains(point: SIMD3<Float>) -> Bool {
        guard point.x > minBounds.x, point.x < maxBounds.x,
              point.y > minBounds.y, point.y < maxBounds.y,
              point.z > minBounds.z, point.z < maxBounds.z else {
            return false
        }
        return true
    }

    /// Checks if this box is in front of the specified plane.
    /// - Parameter plane: the plane to test against.
    /// - Returns: true if any of the box corners are in front of the specifed plane.
    func inFront(of plane: SIMD4<Float>) -> Bool {
        for corner in corners {
            let distance = dot(corner, plane.xyz) + plane.w
            if distance > .zero { return true }
        }
        return false
    }
}
