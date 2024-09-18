//
//  Vim+Camera.swift
//  
//
//  Created by Kevin McKee
//

import Combine
#if canImport(CompositorServices)
import CompositorServices
#endif
import Foundation
import ModelIO
import simd
import Spatial

private let cameraDefaultFovDegrees: Float = 65
private let cameraDefaultAspectRatio: Float = 1.3
private let cameraDefaultNearZ: Float = 0.01
private let cameraDefaultFarZ: Float = 1000.0
private let cameraMaxFov: Float = 179.9

extension Vim {

    public class Camera: NSObject, ObservableObject {

        /// Holds the camera viewing frustum.
        var frustum: Frustum = .init()

        /// Holds our scene rotation transform which is used to
        /// convert from other cameras (such as ARKit or VisionPro).
        var sceneTransform: float4x4 = .identity

        /// The position and orientation of the camera in world coordinate space.
        /// The transform follows left-handed convention where the postive z-axis points up and the
        /// postive y-axis points away from the eye.
        @Published
        public var transform: float4x4 = .identity

        /// The camera projection matrix
        @Published
        public var projectionMatrix: float4x4 = .identity

        /// The view matrix is the matrix that moves everything the opposite
        /// of the camera effectively making everything relative to the camera
        /// as though the camera was at the origin [0,0,0]
        public var viewMatrix: float4x4 {
            return transform.inverse
        }

        /// The field of view in degrees.
        var fovDegrees: Float = cameraDefaultFovDegrees {
            didSet { updateProjection() }
        }

        /// The view port size.
        public var viewportSize: SIMD2<Float> = .zero

        /// The aspect ratio.
        var aspectRatio: Float = cameraDefaultAspectRatio {
            didSet { updateProjection() }
        }

        /// The near clipping plane.
        var nearZ: Float = cameraDefaultNearZ {
            didSet { updateProjection() }
        }

        /// The far clipping plane.
        var farZ: Float = cameraDefaultFarZ {
            didSet { updateProjection() }
        }

        /// Provides the camera right vector.
        public var right: SIMD3<Float> {
            return transform.right
        }

        /// Provides the camera up vector.
        public var up: SIMD3<Float> {
            get { transform.up }
            set(value) {
                transform.up = value
            }
        }

        /// Provides the forward facing direction direction of the camera.
        public var forward: SIMD3<Float> {
            get { transform.forward }
            set(value) {
                lookAt(direction: value)
            }
        }

        /// Provides the position of the camera in world coordinate space.
        public var position: SIMD3<Float> {
            get { transform.position }
            set(value) {
                transform.position = value
            }
        }

        /// Inititalizes the camera with a default position, direction, and up vector.
        /// - Parameters:
        ///   - position: the camera default position
        ///   - direction: the camera forward facing direction
        ///   - up: the camera up vector
        ///   - scale: the scale
        public init(_ position: SIMD3<Float> = .zero, _ direction: SIMD3<Float> = .zero, _ up: SIMD3<Float> = .zpositive, _ scale: Float = -1) {
            super.init()
            update(position, direction, up, scale)
        }

        /// Updates the camera with a new position, direction, and up vector. This method should
        /// be used by observers of the current camera as `.init(...)` calls
        /// will will cause the subscription to drop.
        /// - Parameters:
        ///   - position: the camera default position
        ///   - direction: the camera forward facing direction
        ///   - up: the camera up vector
        ///   - scale: the scale
        public func update(_ position: SIMD3<Float> = .zero, _ direction: SIMD3<Float> = .zero, _ up: SIMD3<Float> = .zpositive, _ scale: Float = -1) {
            self.transform = .init(up: up, scale: scale)
            self.sceneTransform = transform
            self.position = position
            self.forward = direction
            updateProjection()
        }

        /// Updates the projection matrix when any of the relevant projection values change.
        private func updateProjection() {
            let fov = min(fovDegrees, cameraMaxFov)
            let fovyRadians = fov.radians
            let projectiveTransform = ProjectiveTransform3D(fovyRadians: fovyRadians, aspectRatio: aspectRatio, nearZ: nearZ, farZ: farZ)
            projectionMatrix = .init(projectiveTransform)
            frustum.update(self)
        }

        /// Updates the camera by translating and rotating the camera with the specified offsets.
        /// - Parameters:
        ///   - translation: The x, y, z offsets of the current camera position
        ///   - rotation: The x, y, z offsets of the current camera rotation
        ///   - velocity: The velocity multiplier to apply to translation + rotation
        public func navigate(translation: SIMD3<Float>, rotation: SIMD3<Float>, velocity: Float = 1.0) {
            translate(translation: translation * velocity)
            rotate(rotation: rotation * velocity)
            updateProjection()
        }

        /// Rotates the orientation of the camera with the specified offsets.
        /// - Parameters:
        ///   - rotation: The x, y, z offsets of the current camera rotation
        public func rotate(rotation: SIMD3<Float>) {
            let radians = rotation.radians
            let rotations: [(angle: Float, axis: SIMD3<Float>)] = [
                (radians.x, up),
                (radians.y, right.negate)
            ]

            for (angle, axis) in rotations {
                let quaternion = simd_quaternion(angle, axis)
                var matrix = float4x4(quaternion) * transform
                matrix.position = position
                transform = matrix
            }
        }

        /// Sets the camera forward facing direction.
        /// - Parameter direction: the forward facing direction.
        public func lookAt(direction: SIMD3<Float>) {
            guard direction != .zero, var pose = Pose3D(transform) else { return }
            let up = Vector3D(x: up.x, y: up.y, z: up.z)
            let forward = Vector3D(x: direction.x, y: direction.y, z: 1)
            let rotation = Rotation3D(forward: forward, up: up)
            pose.rotate(by: rotation)
            transform = pose.matrix.singlePrecision
        }

        /// Translates the position with the specified offsets along the forward facing direction.
        /// - Parameter translation: the translation offset to apply
        public func translate(translation: SIMD3<Float>) {
            let down = up.inverse
            let r = down * right
            let f = down * forward.negate
            var p = position
            let vector = (normalize(r) * translation.x) + (normalize(f) * translation.y)
            p.x += vector.x
            p.y += vector.y
            p.z += translation.z
            position = p
        }

        /// Projects a point from the 3D world coordinate system of the scene to the 2D pixel coordinate system.
        /// - Parameters:
        ///   - point: A point in the world coordinate system of the scene.
        /// - Returns: The corresponding point in the viewport coordinate system.
        public func projectPoint(_ point: SIMD3<Float>, _ displayScale: Float = 2.0) -> SIMD3<Float> {
            let viewport = SIMD4<Float>(0, 0, viewportSize.x, viewportSize.y)
            let result = project(point: point, modelViewMatrix: viewMatrix, projectionMatrix: projectionMatrix, viewport: viewport)
            let x = result.x / displayScale
            let y = (viewportSize.y - result.y) / displayScale
            return [x, y, result.z]
        }

        /// Unprojects a point from the 2D pixel coordinate system to the 3D world coordinate system of the scene.
        /// See: https://metalbyexample.com/picking-hit-testing/
        /// - Parameters:
        ///   - pixel: A pixel in the screen-space (viewport).
        /// - Returns: the computed position in 3D space
        public func unprojectPoint(_ pixel: SIMD2<Float>) -> Geometry.RaycastQuery {
            let point = SIMD3<Float>(pixel, 1)
            let clipX = (2 * point.x) / viewportSize.x - 1
            let clipY = 1 - (2 * point.y) / viewportSize.y
            let clipSpace = SIMD4<Float>(clipX, clipY, 0, 1)

            var eyeDirection = projectionMatrix.inverse * clipSpace
            eyeDirection.z = -1
            eyeDirection.w = 0

            let worldRayDirection = normalize((viewMatrix.inverse * eyeDirection).xyz)
            return Geometry.RaycastQuery(origin: position, direction: worldRayDirection)
        }

        /// Determines if the camera frustum intersects the bounding box.
        /// - Parameter box: the bounding box to test
        /// - Returns: false if the box is outside the viewing frustum and should be culled.
        func contains(_ box: MDLAxisAlignedBoundingBox) -> Bool {
            frustum.contains(box)
        }

        /// A struct that holds the camera frustum information that contains the
        /// region of space in the modeled world that may appear on the screen.
        /// See: https://lxjk.github.io/2017/04/15/Calculate-Minimal-Bounding-Sphere-of-Frustum.html
        /// See: https://gamedev.stackexchange.com/questions/19774/determine-corners-of-a-specific-plane-in-the-frustum
        struct Frustum {

            /// The plane sides of the camera frustum.
            enum Plane: Int {
                case left
                case right
                case top
                case bottom
                case far
                case near
            }

            /// The frustum clipping planes.
            var planes = [SIMD4<Float>](repeating: .zero, count: 6)

            /// The center point of the frustum bounding sphere.
            var center: SIMD3<Float> = .zero

            /// The minimum bounding sphere radius
            var radius: Float = .zero

            /// Returns the bounding sphere.
            var sphere: Geometry.Sphere {
                Geometry.Sphere(center: center, radius: radius)
            }

            /// Convenience var that returns the frustum near plane
            var nearPlane: SIMD4<Float> {
                return planes[.near]
            }

            /// Convenience var that returns the frustum far plane
            var farPlane: SIMD4<Float> {
                return planes[.far]
            }

            /// Convenience var that returns the frustum left plane
            var leftPlane: SIMD4<Float> {
                return planes[.left]
            }

            /// Convenience var that returns the frustum right plane
            var rightPlane: SIMD4<Float> {
                return planes[.right]
            }

            /// Convenience var that returns the frustum top plane
            var topPlane: SIMD4<Float> {
                return planes[.top]
            }

            /// Convenience var that returns the frustum bottom plane
            var bottomPlane: SIMD4<Float> {
                return planes[.bottom]
            }

            /// Updates the frustum from the specified matrix
            /// - Parameter matrix: the matrix to use to build the frustum planes
            fileprivate mutating func update(_ camera: Camera) {
                let matrix = camera.viewMatrix * camera.projectionMatrix
                // Left Plane
                planes[.left].x = matrix.columns.0.w + matrix.columns.0.x
                planes[.left].y = matrix.columns.1.w + matrix.columns.1.x
                planes[.left].z = matrix.columns.2.w + matrix.columns.2.x
                planes[.left].w = matrix.columns.3.w + matrix.columns.3.x
                // Right Plane
                planes[.right].x = matrix.columns.0.w - matrix.columns.0.x
                planes[.right].y = matrix.columns.1.w - matrix.columns.1.x
                planes[.right].z = matrix.columns.2.w - matrix.columns.2.x
                planes[.right].w = matrix.columns.3.w - matrix.columns.3.x
                // Top Plane
                planes[.top].x = matrix.columns.0.w - matrix.columns.0.y
                planes[.top].y = matrix.columns.1.w - matrix.columns.1.y
                planes[.top].z = matrix.columns.2.w - matrix.columns.2.y
                planes[.top].w = matrix.columns.3.w - matrix.columns.3.y
                // Bottom Plane
                planes[.bottom].x = matrix.columns.0.w + matrix.columns.0.y
                planes[.bottom].y = matrix.columns.1.w + matrix.columns.1.y
                planes[.bottom].z = matrix.columns.2.w + matrix.columns.2.y
                planes[.bottom].w = matrix.columns.3.w + matrix.columns.3.y
                // Near (Back) Plane
                planes[.near].x = matrix.columns.0.w + matrix.columns.0.z
                planes[.near].y = matrix.columns.1.w + matrix.columns.1.z
                planes[.near].z = matrix.columns.2.w + matrix.columns.2.z
                planes[.near].w = matrix.columns.3.w + matrix.columns.3.z
                // Far (Front) Plane
                planes[.far].x = matrix.columns.0.w - matrix.columns.0.z
                planes[.far].y = matrix.columns.1.w - matrix.columns.1.z
                planes[.far].z = matrix.columns.2.w - matrix.columns.2.z
                planes[.far].w = matrix.columns.3.w - matrix.columns.3.z

                for (i, _) in planes.enumerated() {
                    planes[i] = normalize(planes[i])
                }

                // Calculate the sphere center + radius
                let p = camera.position
                let f = camera.forward
                let nearCenter = p + f * camera.nearZ
                let farCenter = p + f * -camera.farZ

                let c = (nearCenter + farCenter) * .half
                let d = distance(c, nearCenter) - camera.nearZ

                center = c
                radius = d
            }

            /// Tests to see if the frustum contains the provided bounding box or not.
            /// - Parameters:
            ///   - box: the bounding box to test
            ///   - radius: the sphere radius
            /// - Returns: true if contains, otherwise false
            func contains(_ box: MDLAxisAlignedBoundingBox) -> Bool {
                if !sphere.contains(box: box) {
                    // Test the planes against the box
                    let position = box.center
                    let radius = box.radius
                    for plane in planes {
                        let d = (plane.x * position.x) + (plane.y * position.y) + (plane.z * position.z) + plane.w
                        if d <= -radius {
                            return false
                        }
                    }
                }
                return true
            }
        }
    }
}

fileprivate extension Array where Element == SIMD4<Float> {

    subscript(_ side: Vim.Camera.Frustum.Plane) -> SIMD4<Float> {
        get {
            return self[side.rawValue]
        }
        set {
            self[side.rawValue] = newValue
        }
    }
}

#if os(visionOS)

extension Vim.Camera {

    /// Updates the camera transform from the drawable view at the specifed index.
    /// - Parameters:
    ///   - drawable: the drawable
    ///   - index: the view index
    ///   - velocity: the velocity multiplier to apply to translation.
    public func update(_ drawable: LayerRenderer.Drawable, index: Int, velocity: Float = 1.5) {

        // Get the current device anchor
        guard let deviceAnchor = drawable.deviceAnchor else { return }

        let view = drawable.views[index]
        let tangents = view.tangents
        let depthRange = drawable.depthRange

        let projectiveTransform = ProjectiveTransform3D(tangents: tangents, depthRange: depthRange)
        projectionMatrix = .init(projectiveTransform)
        transform = sceneTransform * deviceAnchor.originFromAnchorTransform
        position *= velocity
        frustum.update(self)
    }
}

#endif
