//
//  Geometry+Raycasting.swift
//  
//
//  Created by Kevin McKee
//

import MetalKit
import simd

extension Geometry {

    /// A type used to find an instance by examining a point on the screen.
    public struct RaycastQuery {

        /// A 3D coordinate that defines the ray's starting point.
        var origin: SIMD3<Float>
        /// A vector that describes the ray's trajectory in 3D space.
        var direction: SIMD3<Float>

        /// Initializer
        /// - Parameters:
        ///   - origin: the ray origin
        ///   - direction: the direction of the ray
        public init(origin: SIMD3<Float>, direction: SIMD3<Float>) {
            self.origin = origin
            self.direction = direction
        }

        /// Determine the point along this ray at the given parameter
        func extrapolate(_ parameter: Float) -> SIMD4<Float> {
            return .init(origin + parameter * direction, 1)
        }

        /// Determine the parameter corresponding to the point,
        /// assuming it lies on this ray
        func interpolate(_ point: SIMD4<Float>) -> Float {
            return length(point.xyz - origin) / length(direction)
        }

        /// Convenience operator that performs multiplication of the transform against the query.
        /// - Parameters:
        ///   - transform: the transform
        ///   - query: the raycast query
        /// - Returns: a new raycast query multiplied by the transform.
        static func * (transform: float4x4, query: RaycastQuery) -> RaycastQuery {
            let o = (transform * SIMD4<Float>(query.origin, 1)).xyz
            let d = (transform * SIMD4<Float>(query.direction, 0)).xyz
            return RaycastQuery(origin: o, direction: d)
        }

        /// Returns the plane intersection result if found.
        /// - Parameter plane: the plane to intersect
        /// - Returns: the plane intersection result.
        fileprivate func intersection(plane: SIMD4<Float>) -> SIMD4<Float>? {
            let directionDotNorm = dot(direction, plane.xyz)
            guard directionDotNorm != .zero else { return nil }
            let distance = -(dot(origin, plane.xyz) + plane.w) / dot(direction, plane.xyz)
            let location = origin + (direction * distance)
            return .init(location, distance)
        }
    }

    /// A type that holds information about the result for a raycast query.
    public struct RaycastResult {

        /// The query that produced this result.
        public let query: RaycastQuery
        /// The distance from the origin to the result.
        public let distance: Float
        /// The position of the intersection result in world space
        public var position: SIMD3<Float> {
            query.origin + distance * query.direction
        }

        /// Initializer.
        /// - Parameters:
        ///   - query: the query that produced this result
        ///   - distance: the distance to the face that was intersected
        init(query: RaycastQuery, distance: Float) {
            self.query = query
            self.distance = distance
        }

        /// Convenience operator that tests if the lest hand side result is less than the right hand result.
        /// - Parameters:
        ///   - lhs: the left hand result to test against
        ///   - rhs: the right hand result to test against
        /// - Returns: true if the left hand result distance is less than the right hand side result.
        static func < (lhs: RaycastResult, rhs: RaycastResult) -> Bool {
            lhs.distance < rhs.distance
        }
    }
}

// MARK: Hit Testing

extension Geometry.RaycastQuery {

    /// Convenience method that tests if the query intersects the face.
    /// - Parameter face: the face to test
    /// - Returns: the raycast result if the face intersects.
    fileprivate func hitTest(face: Geometry.Face) -> Geometry.RaycastResult? {
        hitTest(face.a, face.b, face.c)
    }

    /// Tests if the query intersects the triangle.
    /// - SeeAlso: https://en.wikipedia.org/wiki/M%C3%B6ller%E2%80%93Trumbore_intersection_algorithm
    /// - Parameters:
    ///   - pa: the first point of the triange
    ///   - pb: the second point of the triangle
    ///   - pc: the third point of the triangle
    /// - Returns: the raycast result if the triangle intersects.
    fileprivate func hitTest(_ pa: SIMD3<Float>, _ pb: SIMD3<Float>, _ pc: SIMD3<Float>) -> Geometry.RaycastResult? {

        let edgeA = pb - pa
        let edgeB = pc - pa
        let h = cross(direction, edgeB)
        let det = dot(edgeA, h)
        let epsilon: Float = .ulpOfOne

        // The ray is parallel to this triangle
        if det > -epsilon && det < epsilon {
            return nil
        }

        let invDet = 1.0 / det
        let s = origin - pa
        let u = invDet * dot(s, h)

        if u < .zero || u > 1.0 {
            return nil
        }

        let q = cross(s, edgeA)
        let v = dot(direction, q) * invDet

        if v < .zero || (u + v) > 1.0 {
            return nil
        }

        // At this stage we can compute t to find out where the intersection point is on the line.
        let distance = invDet * dot(edgeB, q)

        if distance > epsilon {
            return Geometry.RaycastResult(query: self, distance: distance)
        } else {
            // Line intersection, but not a ray intersection.
            return nil
        }
    }
}

// MARK: Instance Querying

extension Geometry.Instance {

    /// Performs an intersection test of the instance against the query.
    /// If the instance has a large number of submeshes, then the bounding box is used as an estimate.
    /// - Parameters:
    ///   - geometry: the geometry container that holds the instance mesh and submesh
    ///   - query: the raycast query.
    /// - Returns: the result of the query.
    func raycast(_ geometry: Geometry, query: Geometry.RaycastQuery) -> Geometry.RaycastResult? {

        guard let faces = geometry.faces(for: self), faces.isNotEmpty else { return nil }
        var results = [Geometry.RaycastResult]()

        for face in faces {
            if let result = query.hitTest(face: face) {
                results.append(result)
            }
        }
        // Sort the results by distance and return the first one
        return results.sorted{ $0.distance < $1.distance }.first
    }
}

// MARK: MDLAxisAlignedBoundingBox Querying

extension MDLAxisAlignedBoundingBox {

    /// Performs an intersection test.
    /// - Parameter query: the raycast query
    /// - Returns: true if the ray intersects this box.
    func intersects(_ query: Geometry.RaycastQuery) -> Bool {

        var xMin = (minBounds.x - query.origin.x) / query.direction.x
        var xMax = (maxBounds.x - query.origin.x) / query.direction.x
        if xMin > xMax {
            swap(&xMin, &xMax)
        }

        var yMin = (minBounds.y - query.origin.y) / query.direction.y
        var yMax = (maxBounds.y - query.origin.y) / query.direction.y
        if yMin > yMax {
            swap(&yMin, &yMax)
        }

        if (xMin > yMax) || (yMin > xMax) {
            return false
        }

        if yMin > xMin {
            xMin = yMin
        }

        if yMax < xMax {
            xMax = yMax
        }

        var zMin = (minBounds.z - query.origin.z) / query.direction.z
        var zMax = (maxBounds.z - query.origin.z) / query.direction.z

        if zMin > zMax {
            swap(&zMin, &zMax)
        }

        if (xMin > zMax) || (zMin > xMax) {
            return false
        }

        if zMin > xMin {
            xMin = zMin
        }

        if zMax < xMax {
            xMax = zMax
        }
        return true
    }

    /// Performs an intersection test of the bounding box against the query.
    /// - Parameter query: the raycast query.
    /// - Returns: the raycast result of the query.
    func raycast(_ query: Geometry.RaycastQuery) -> Geometry.RaycastResult? {
        var position: SIMD4<Float> = .invalid
        intersection(query, sideNormal: .xpositive, position: &position)
        intersection(query, sideNormal: .xnegative, position: &position)
        intersection(query, sideNormal: .ypositive, position: &position)
        intersection(query, sideNormal: .ynegative, position: &position)
        intersection(query, sideNormal: .zpositive, position: &position)
        intersection(query, sideNormal: .znegative, position: &position)
        guard position != .invalid else { return nil }
        let d = distance(query.origin, position.xyz)
        return Geometry.RaycastResult(query: query, distance: d)
    }

    /// Performs an intersection test of the bounding box against the query.
    /// - Parameters:
    ///   - query: the ray cast query.
    ///   - sideNormal: the side normal
    ///   - hit: the updated hit
    private func intersection(_ query: Geometry.RaycastQuery, sideNormal: SIMD3<Float>, position: inout SIMD4<Float>) {
        let corner = sideNormal.x + sideNormal.y + sideNormal.z > .zero ? maxBounds : minBounds
        let sidePlane = SIMD4<Float>(sideNormal, -dot(corner, sideNormal))

        guard var sideHit = query.intersection(plane: sidePlane), sideHit.w > .zero else {
            return
        }

        if sideNormal.x == 1.0 { sideHit.x = corner.x }
        if sideNormal.y == 1.0 { sideHit.y = corner.y }
        if sideNormal.z == 1.0 { sideHit.z = corner.z }

        if sideHit.w < position.w {
            position = sideHit
        }
    }
}

