![Build](https://github.com/codefiesta/VimKit/actions/workflows/swift.yml/badge.svg)
![Xcode 16.0+](https://img.shields.io/badge/Xcode-16.0%2B-gold.svg)
![Swift 6.0+](https://img.shields.io/badge/Swift-6.0%2B-tomato.svg)
![iOS 17.0+](https://img.shields.io/badge/iOS-17.0%2B-crimson.svg)
![visionOS 1.0+](https://img.shields.io/badge/visionOS-1.0%2B-magenta.svg)
![macOS 15.0+](https://img.shields.io/badge/macOS-15.0%2B-skyblue.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-indigo.svg)](https://opensource.org/licenses/MIT)

# VimKit
VimKit is an open-source [swift package](https://developer.apple.com/documentation/xcode/swift-packages) for reading and rendering [VIM](https://www.vimaec.com/) files on Apple platforms ([iOS](https://developer.apple.com/ios/), [macOS](https://developer.apple.com/macos/), [visionOS](https://developer.apple.com/visionos/)) with [Metal](https://developer.apple.com/metal/).

https://github.com/user-attachments/assets/a4b4add6-545c-47b8-8962-e24d2f1b666b

## Overview
The VimKit package is broken down into 3 seperate modules ([VimKit](#vimkit-1), [VimKitCompositor](#vimkitcompositor), [VimKitShaders](#vimkitshaders)). 

[VIM](https://github.com/vimaec/vim) files are composed of [BFAST](https://github.com/vimaec/bfast) containers that provide the necessary [geometry](https://github.com/vimaec/vim#geometry-buffer), [assets](https://github.com/vimaec/vim/#assets-buffer), [entities](https://github.com/vimaec/vim#entities-buffer), and [strings](https://github.com/vimaec/vim#strings-buffer) buffers used to render and interrogate all of the 3D instances contained in a file. 

Although it is possible to render each [Instance](https://github.com/codefiesta/VimKit/blob/main/Sources/VimKitShaders/include/ShaderTypes.h#L93) individually, VimKit leverages instancing to render all Instance's that share the same Mesh in a single [draw](https://github.com/codefiesta/VimKit/blob/main/Sources/VimKit/Renderer/VimRenderer%2BDrawing.swift) call.

[Geometry.swift](https://github.com/codefiesta/VimKit/blob/main/Sources/VimKit/Geometry.swift) and [ShaderTypes.h](https://github.com/codefiesta/VimKit/blob/main/Sources/VimKitShaders/include/ShaderTypes.h) are the best sources to understand the details of how the geometry, positions, indices and data structures used for rendering are organized.

## VimKit
Provides the core library for reading and [rendering](https://github.com/codefiesta/VimKit/blob/main/Sources/VimKit/Renderer/VimRenderer.swift) VIM files on [macOS](https://developer.apple.com/macos/) and [iOS](https://developer.apple.com/ios/).

### References
*  [https://github.com/vimaec/vim-format](https://github.com/vimaec/vim-format)
*  [https://github.com/vimaec/bfast](https://github.com/vimaec/bfast)
*  [https://github.com/vimaec/g3d](https://github.com/vimaec/g3d)


## VimKitCompositor
Provides the core library for rendering VIM files on [visionOS](https://developer.apple.com/visionos/) (Apple Vision Pro) using [CompositorServices](https://developer.apple.com/documentation/compositorservices).

### References
*  [WWDC 2023 - Discover Metal for immersive apps](https://developer.apple.com/videos/play/wwdc2023/10089/)
*  [WWDC 2023 - Meet ARKit for spatial computing](https://developer.apple.com/videos/play/wwdc2023/10082)
*  [Drawing fully immersive content using Metal](https://developer.apple.com/documentation/compositorservices/drawing_fully_immersive_content_using_metal)

## VimKitShaders
C Library that provides types and enums shared between [Metal Shaders](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf) and Swift.


## VisionOS Usage
The following is an example of the simplest usage of rendering a VIM file on visionOS:

```swift
import CompositorServices
import SwiftUI
import VimKit
import VimKitCompositor

/// The id of our immersive space
fileprivate let immersiveSpaceId = "VimImmersiveSpace"

@main
struct VimViewerApp: App {

    /// Sample Vim File
    let vim = Vim(URL(string: "https://vim02.azureedge.net/samples/residence.v1.2.75.vim")!)

    /// Holds the composite layer configuration
    let configuration = VimCompositorLayerConfiguration()

    /// The ARKit DataProvider context
    let dataProviderContext = DataProviderContext()

    /// Build the scene body
    var body: some Scene {

        // Displays a 2D Window
        WindowGroup {
            Button {
                Task {
                    // Launch the immersive space
                    await openImmersiveSpace(id: immersiveSpaceId)
                }
            } label: {
                Text("Show Immersive Space")
            }
            .task {
                // Start the ARKit HandTracking
                await dataProviderContext.start()
            }
        }

        // Displays the fully immersive 3D scene
        ImmersiveSpace(id: immersiveSpaceId) {
            VimImmersiveSpaceContent(vim: vim,
                                     configuration: configuration,
                                     dataProviderContext: dataProviderContext)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
} 
```

