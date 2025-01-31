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

private let defaultFovDegrees: Float = 65
private let defaultAspectRatio: Float = 1.3
private let defaultNearZ: Float = 0.1
private let defaultFarZ: Float = 1000.0

extension Vim {

    /// Provides a right-handed 3D camera with Z as the default up axis.
    public class Camera: NSObject, ObservableObject {

        /// Holds the camera viewing frustum.
        public var frustum: Frustum = .init()

        /// The clipping planes to apply.
        public var clipPlanes = [SIMD4<Float>](repeating: .invalid, count: 6)

        /// Holds our scene rotation transform which is used to
        /// convert from other cameras (such as ARKit or VisionPro).
        public var sceneTransform: float4x4 = .identity

        /// The position and orientation of the camera in world coordinate space.
        /// The transform follows left-handed convention where the postive z-axis points up and the
        /// postive y-axis points away from the eye.
        @Published
        public var transform: float4x4 = .identity {
            didSet { updateProjection() }
        }

        /// The camera projection matrix
        public var projectionMatrix: float4x4 = .identity

        /// The view matrix is the matrix that moves everything the opposite
        /// of the camera effectively making everything relative to the camera
        /// as though the camera was at the origin [0,0,0]
        public var viewMatrix: float4x4 {
            transform.inverse
        }

        /// The field of view in degrees.
        var fovDegrees: Float = defaultFovDegrees {
            didSet { updateProjection() }
        }

        /// The view port size.
        public var viewportSize: SIMD2<Float> = .zero

        /// The aspect ratio.
        var aspectRatio: Float = defaultAspectRatio {
            didSet { updateProjection() }
        }

        /// The near clipping plane.
        var nearZ: Float = defaultNearZ {
            didSet { updateProjection() }
        }

        /// The far clipping plane.
        var farZ: Float = defaultFarZ {
            didSet { updateProjection() }
        }

        /// The transform scale.
        public var scale: SIMD3<Float> {
            get { transform.scale }
            set(value) {
                transform.scale(value)
            }
        }

        // MARK: Directional vectors (all derived from the transform up and direction vectors).

        /// Provides the camera right vector.
        public var right: SIMD3<Float> {
            transform.right
        }

        /// Provides the camera left vector.
        public var left: SIMD3<Float> {
            right.inverse
        }

        /// Provides the camera up vector.
        public var up: SIMD3<Float> {
            get { transform.up }
            set(value) {
                transform.up = value
            }
        }

        /// Provides the camera down vector.
        public var down: SIMD3<Float> {
            up.inverse
        }

        /// Provides the forward facing direction direction of the camera.
        public var forward: SIMD3<Float> {
            get { transform.forward }
            set(value) {
                look(in: value)
            }
        }

        /// Provides the backward facing direction direction of the camera.
        public var backward: SIMD3<Float> {
            forward.negate
        }

        /// Provides the position of the camera in world coordinate space.
        public var position: SIMD3<Float> {
            get { transform.position }
            set(value) {
                transform.position = value
            }
        }

        /// Common Initializer
        override public init() {
            super.init()
            self.transform = .init(position: .zero, target: .ynegative, up: .zpositive)
            self.sceneTransform = transform
        }

        /// Updates the projection matrix when any of the relevant projection values change.
        private func updateProjection() {
            let fov = fovDegrees
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
            transform.rotate(by: radians)
        }

        /// Constructs a look at matrix from the target point, the position and up vector. If the position is not specified, the current camera position will be used.
        /// - Parameters:
        ///   - target: The target position to look at.
        ///   - position: The new position of the camera.
        ///   - upVector: The new  camera up vector.
        public func look(at target: SIMD3<Float>, from position: SIMD3<Float>? = nil, upVector: SIMD3<Float>? = nil) {
            if let position {
                self.position = position
            }

            // Avoid gimble lock from shitty camera
            let upVector = upVector == nil ? .zpositive : upVector!
            let target = target == upVector ? .ynegative : target

            // Construct a new look at matrix
            transform = .init(position: self.position, target: target, up: upVector)
        }

        /// Constructs a look at matrix from the directional vector, position and up vector. If the position is not specified, the current camera position will be used.
        /// - Parameters:
        ///   - direction: The directional vector to use.
        ///   - position: The new position of the camera.
        ///   - upVector: The new camera up vector.
        public func look(in direction: SIMD3<Float>, from position: SIMD3<Float>? = nil, upVector: SIMD3<Float>? = nil) {
            if let position {
                self.position = position
            }

            let target = self.position + direction
            look(at: target, from: position, upVector: upVector)
        }

        /// Translates the position with the specified offsets along the forward facing direction.
        /// - Parameter translation: the translation offset to apply
        public func translate(translation: SIMD3<Float>) {

            // Calculate the translation vector
            let x = right
            let y = backward
            let vector = (normalize(x) * translation.x) + (normalize(y) * translation.y)

            // Update the position
            var p = position
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
            return .init(x: x, y: y, z: result.z)
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
            return .init(origin: position, direction: worldRayDirection)
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
        public struct Frustum {

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
            public var planes = [SIMD4<Float>](repeating: .zero, count: 6)

            /// Convenience var that returns the frustum near plane
            var nearPlane: SIMD4<Float> {
                planes[.near]
            }

            /// Convenience var that returns the frustum far plane
            var farPlane: SIMD4<Float> {
                planes[.far]
            }

            /// Convenience var that returns the frustum left plane
            var leftPlane: SIMD4<Float> {
                planes[.left]
            }

            /// Convenience var that returns the frustum right plane
            var rightPlane: SIMD4<Float> {
                planes[.right]
            }

            /// Convenience var that returns the frustum top plane
            var topPlane: SIMD4<Float> {
                planes[.top]
            }

            /// Convenience var that returns the frustum bottom plane
            var bottomPlane: SIMD4<Float> {
                planes[.bottom]
            }

            /// Updates the frustum from the specified matrix
            /// - Parameter matrix: the matrix to use to build the frustum planes
            fileprivate mutating func update(_ camera: Camera) {
                let matrix = (camera.projectionMatrix * camera.viewMatrix).transpose

                planes[.left] = matrix.columns.3 + matrix.columns.0
                planes[.right] = matrix.columns.3 - matrix.columns.0
                planes[.bottom] = matrix.columns.3 + matrix.columns.1
                planes[.top] = matrix.columns.3 - matrix.columns.1
                planes[.near] = matrix.columns.2
                planes[.far] = matrix.columns.3 - matrix.columns.2

                for (i, _) in planes.enumerated() {
                    planes[i] = normalize(planes[i])
                }
            }

            /// Tests to see if the frustum contains the provided bounding box or not.
            /// See: https://ktstephano.github.io/rendering/stratusgfx/aabbs
            /// - Parameters:
            ///   - box: the bounding box to test
            /// - Returns: true if contains, otherwise false
            func contains(_ box: MDLAxisAlignedBoundingBox) -> Bool {
                let corners = box.corners
                for plane in planes {
                    if dot(plane, SIMD4<Float>(corners[0], 1.0)) < .zero &&
                        dot(plane, SIMD4<Float>(corners[1], 1.0)) < .zero &&
                        dot(plane, SIMD4<Float>(corners[2], 1.0)) < .zero &&
                        dot(plane, SIMD4<Float>(corners[3], 1.0)) < .zero &&
                        dot(plane, SIMD4<Float>(corners[4], 1.0)) < .zero &&
                        dot(plane, SIMD4<Float>(corners[5], 1.0)) < .zero &&
                        dot(plane, SIMD4<Float>(corners[6], 1.0)) < .zero &&
                        dot(plane, SIMD4<Float>(corners[7], 1.0)) < .zero
                     {
                        // Not visible - all returned negative
                        return false
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
            self[side.rawValue]
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

        let projection = drawable.computeProjection(convention: .rightUpForward, viewIndex: index)
        projectionMatrix = projection
        transform = sceneTransform * deviceAnchor.originFromAnchorTransform
        position *= velocity
        frustum.update(self)
    }
}

#endif
