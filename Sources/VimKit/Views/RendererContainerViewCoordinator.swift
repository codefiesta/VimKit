//
//  RendererContainerViewCoordinator.swift
//  
//
//  Created by Kevin McKee
//

import GameController
import MetalKit

#if !os(visionOS)

/// Keyboard navigation keys.
private let keys: [GCKeyCode] = [
    .keyW,
    .keyS,
    .keyA,
    .keyD,
    .keyE,
    .keyQ,
    .leftArrow,
    .upArrow,
    .rightArrow,
    .downArrow
]

/// Provides a coordinator that is responsible for rendering into it's MTKView representable.
@MainActor
public class RendererContainerViewCoordinator: NSObject, MTKViewDelegate {

    let renderer: Renderer
    let viewRepresentable: RendererContainerView

    /// Initializes the coordinator with the specified view representable.
    /// - Parameter viewRepresentable: the MTKView representable
    init(_ viewRepresentable: RendererContainerView) {
        self.viewRepresentable = viewRepresentable
        self.renderer = Renderer(viewRepresentable.renderContext)
        super.init()
        #if os(macOS)
        // Prevent the macOS beeping on keyDown events
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { _ in nil }
        #endif
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.mtkView(view, drawableSizeWillChange: size)
    }

    public func draw(in view: MTKView) {
        pollKeyboardInput()
        renderer.draw(in: view)
    }
}

// MARK: Gesture Recognizers

extension RendererContainerViewCoordinator {

#if os(macOS)

    @objc
    func handleTap(_ gesture: NSGestureRecognizer) {
        guard let view = gesture.view, let screen = NSScreen.main else { return }
        switch gesture.state {
        case .recognized:
            let contentScaleFactor = Float(screen.backingScaleFactor)
            // NSView 0,0 is in the lower left with positive values of Y going up.
            // where UIView 0,0 is in the top left with positive values of Y going down
            let frame = view.frame
            let location = gesture.location(in: view)

            let y = frame.height - location.y // Flip the Y coordinate
            let point: SIMD2<Float> = [Float(location.x), Float(y)]
            renderer.didTap(at: point, contentScaleFactor)
        default:
            break
        }
    }

#else

    @objc
    func handleTap(_ gesture: UIGestureRecognizer) {
        guard let view = gesture.view else { return }
        switch gesture.state {
        case .recognized:
            let contentScaleFactor = Float(view.contentScaleFactor)
            let location = gesture.location(in: view)
            let point: SIMD2<Float> = [Float(location.x), Float(location.y)]
            renderer.didTap(at: point, contentScaleFactor)
        default:
            break
        }
    }
#endif
}

// MARK: Keyboard Events

extension RendererContainerViewCoordinator {

    // Navigates the current model with keyboard events
    fileprivate func keyPressed(keyCode: GCKeyCode) {
        var translation: SIMD3<Float> = .zero
        var rotation: SIMD3<Float> = .zero
        switch keyCode {
        case .keyW:
            // Forward
            translation.y = 1.0
        case .keyS:
            // Back
            translation.y = -1.0
        case .keyA:
            // Left
            translation.x = -1.0
        case .keyD:
            // Right
            translation.x = 1.0
        case .keyE:
            // Up
            translation.z = 1.0
        case .keyQ:
            // Down
            translation.z = -1.0
        case .leftArrow:
            // Rotate left
            rotation.y = -1.0
        case .rightArrow:
            // Rotate Right
            rotation.y = 1.0
        case .upArrow:
            // Rotate up
            rotation.x = 1.0
        case .downArrow:
            // Rotate down
            rotation.x = -1.0
        default:
            break
        }
        renderer.context.vim.camera.navigate(translation: translation, rotation: rotation)
    }

    // Non-blocking polling for keyboard keys being pressed
    // See: https://developer.apple.com/videos/play/wwdc2020/10617
    func pollKeyboardInput() {
        guard let keyboard = GCKeyboard.coalesced?.keyboardInput else { return }
        for key in keys {
            if keyboard.button(forKeyCode: key)?.isPressed ?? false {
                keyPressed(keyCode: key)
            }
        }
    }
}

#endif
