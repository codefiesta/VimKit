//
//  VimContainerViewCoordinator.swift
//  
//
//  Created by Kevin McKee
//

import GameController
import MetalKit

#if os(iOS)
/// Provides a coordinator that is responsible for rendering into it's MTKView representable.
public class VimContainerViewCoordinator: NSObject, MTKViewDelegate {

    let renderer: VimRenderer
    let viewRepresentable: VimContainerView

    /// Initializes the coordinator with the specified view representable.
    /// - Parameter viewRepresentable: the MTKView representable
    init(_ viewRepresentable: VimContainerView) {
        self.viewRepresentable = viewRepresentable
        self.renderer = VimRenderer(viewRepresentable.renderContext)
        super.init()
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

extension VimContainerViewCoordinator {

    @objc
    func handleTap(_ gesture: UITapGestureRecognizer) {

        guard let view = gesture.view else { return }
        switch gesture.state {
        case .recognized:
            let location = gesture.location(in: view) * view.contentScaleFactor
            let point: SIMD2<Float> = [Float(location.x), Float(location.y)]
            renderer.didTap(at: point)
        default:
            break
        }
    }
}

// MARK: Keyboard Events

extension VimContainerViewCoordinator {

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
            rotation.x = 1.0
        case .rightArrow:
            // Rotate Right
            rotation.x = -1.0
        case .upArrow:
            // Rotate up
            rotation.y = 1.0
        case .downArrow:
            // Rotate down
            rotation.y = -1.0
        default:
            break
        }
        renderer.context.vim.camera.navigate(translation: translation, rotation: rotation)
    }

    // Non-blocking polling for keyboard keys being pressed
    // See: https://developer.apple.com/videos/play/wwdc2020/10617
    func pollKeyboardInput() {
        guard let keyboard = GCKeyboard.coalesced?.keyboardInput else { return }
        let keys: [GCKeyCode] = [.keyW, .keyS, .keyA, .keyD, .keyE, .keyQ, .leftArrow, .upArrow, .rightArrow, .downArrow]
        for key in keys {
            if keyboard.button(forKeyCode: key)?.isPressed ?? false {
                keyPressed(keyCode: key)
            }
        }
    }
}

#endif
