//
//  CompositorRenderer+SpatialEvents.swift
//
//
//  Created by Kevin McKee
//

#if canImport(CompositorServices)
import SwiftUI
import VimKit

public extension CompositorRenderer {

    /// Handle spatial events.
    ///
    /// - These events are delivered on the main thread so we'll need synchronization
    /// - Parameter events: The array of events to handle
    func handle(events: [SpatialEventCollection.Element]) {

        // TODO: Lock

        // Copy the events into an internal queue
        for event in events {
            switch event.kind {
            case .touch:
                handleTouch(event)
            case .directPinch:
                handleDirectPinch(event)
            case .indirectPinch:
                handleIndirectPinch(event)
            case .pointer:
                handlePointer(event)
            @unknown default:
                break
            }
        }

        // TODO: Unlock
    }

    /// Handles touch events generated from a touch directly targeting content.
    /// - Parameter event: The event to handle
    private func handleTouch(_ event: SpatialEventCollection.Element) {

    }

    /// Handles direct pinch events generated from a pinching hand in close proximity to content.
    /// - Parameter event: The event to handle
    private func handleDirectPinch(_ event: SpatialEventCollection.Element) {

    }

    /// Handles indirect pinch events generated from an indirectly targeted pinching hand.
    /// - Parameter event: The event to handle
    private func handleIndirectPinch(_ event: SpatialEventCollection.Element) {
        switch event.phase {
        case .active:
            break
        case .ended:
            break
        case .cancelled:
            break
        @unknown default:
            break
        }
    }

    /// Handles pointer events representing a click-based, indirect input device describing the input sequence from click to click release.
    /// - Parameter event: The event to handle
    private func handlePointer(_ event: SpatialEventCollection.Element) {

    }
}

#endif
