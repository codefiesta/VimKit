//
//  DataProviderContext.swift
//
//
//  Created by Kevin McKee
//
#if canImport(CompositorServices)

import ARKit
import SwiftUI

/// Provides an observable context that contains up-to-date
public class DataProviderContext: ObservableObject, @unchecked Sendable {

    public struct HandUpdates {
        var left: HandAnchor?
        var right: HandAnchor?
    }

    let session = ARKitSession()
    var handTrackingProvider = HandTrackingProvider()
    var worldTrackingProvider = WorldTrackingProvider()

    /// The transform from the world anchor to the origin coordinate system.
    @Published
    public var transform: float4x4 = .identity

    @Published
    public var handUpdates: HandUpdates = .init(left: nil, right: nil)

    public init() { }

    /// Starts the ARSession to begin monitoring hand tracking for interaction and touch events.
    @MainActor
    public func start() async {
        do {

            var providers: [DataProvider] = [worldTrackingProvider]

            if HandTrackingProvider.isSupported {
                providers.append(handTrackingProvider)

                let query = await session.queryAuthorization(for: [.handTracking])
                debugPrint("2️⃣", query)
                if let status = query[.handTracking] {
                    debugPrint("✅", status)
                    switch status {
                    case .allowed:
                        break
                    case .denied, .notDetermined:
                        _ = await session.requestAuthorization(for: [.handTracking])
                    @unknown default:
                        break
                    }
                }
            }

            try await session.run(providers)
            debugPrint("✅", session)
        } catch {
            print("ARKitSession error:", error)
        }
    }

    public func monitorSessionEvents() async {
        for await event in session.events {
            debugPrint("🗳️", event)
            switch event {
            case .authorizationChanged(let type, let status):
                if type == .handTracking && status != .allowed {
                    // Stop the rendering, ask the user to grant hand tracking authorization again in Settings.
                }
            case .dataProviderStateChanged:
                break
            @unknown default:
                print("Session event \(event)")
            }
        }
    }

    public func publishHandTrackingUpdates() async {
        for await update in handTrackingProvider.anchorUpdates {
            switch update.event {
            case .updated:
                let anchor = update.anchor
                // Publish updates only if the hand and the relevant joints are tracked.
                guard anchor.isTracked else { continue }

                // Update left hand info.
                if anchor.chirality == .left {
                    handUpdates.left = anchor
                } else if anchor.chirality == .right { // Update right hand info.
                    handUpdates.right = anchor
                }
            default:
                break
            }
        }
    }

    public func publishWorldTrackingUpdates() async {
        for await event in worldTrackingProvider.anchorUpdates {
            debugPrint("🆔", event)
            switch event.event {
            case .updated:
                transform = event.anchor.originFromAnchorTransform
            default:
                break
            }
        }
    }

    /// Query the device anchor at a given timestamp.
    /// - Parameter timestamp: timestamp the timestamp used to predict the device pose
    /// - Returns: The predicted position and orientation of the device at the given timestamp.
    func queryDeviceAnchor(_ timestamp: TimeInterval) -> DeviceAnchor? {
        worldTrackingProvider.queryDeviceAnchor(atTimestamp: timestamp)
    }
}

#endif
