![Build](https://github.com/codefiesta/VimKit/actions/workflows/swift.yml/badge.svg)
![Swift 6.2+](https://img.shields.io/badge/Swift-6.2%2B-gold.svg)
![Xcode 26.0+](https://img.shields.io/badge/Xcode-26.0%2B-tomato.svg)
![iOS 26.0+](https://img.shields.io/badge/iOS-26.0%2B-crimson.svg)
![macOS 26.0+](https://img.shields.io/badge/macOS-26.0%2B-skyblue.svg)
![visionOS 26.0+](https://img.shields.io/badge/visionOS-2.0%2B-violet.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-indigo.svg)](https://opensource.org/licenses/MIT)

# VimKit
VimKit is an open-source [swift package](https://developer.apple.com/documentation/xcode/swift-packages) for reading and rendering [VIM](https://www.vimaec.com/) files on Apple platforms ([iOS](https://developer.apple.com/ios/), [macOS](https://developer.apple.com/macos/), [visionOS](https://developer.apple.com/visionos/)) with [Metal](https://developer.apple.com/metal/).

https://github.com/user-attachments/assets/fbf67c6d-5195-43ba-83e6-1201a992c0de


## Overview
The VimKit package is broken down into 3 seperate modules ([VimKit](#vimkit-1), [VimKitCompositor](#vimkitcompositor), [VimKitShaders](#vimkitshaders)). 

[VIM](https://github.com/vimaec/vim) files are composed of [BFAST](https://github.com/vimaec/bfast) containers that provide the necessary [geometry](https://github.com/vimaec/vim#geometry-buffer), [assets](https://github.com/vimaec/vim/#assets-buffer), [entities](https://github.com/vimaec/vim#entities-buffer), and [strings](https://github.com/vimaec/vim#strings-buffer) buffers used to render and interrogate all of the 3D instances contained in a file. 

Although it is possible to render each [Instance](https://github.com/codefiesta/VimKit/blob/main/Sources/VimKitShaders/include/ShaderTypes.h#L109) individually, VimKit leverages instancing to render all Instance's that share the same Mesh in a single [draw](https://github.com/codefiesta/VimKit/blob/main/Sources/VimKit/Renderer/Renderer%2BDrawing.swift) call.

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
Provides the core Metal C++14 Library that provides types and enums shared between [Metal Shaders](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf) and Swift.

## Direct and Indirect Rendering
VimKit supports both Direct Render Passes (draw commands issued on the CPU) and Indirect Render Passes (draw commands issued on the GPU via [Indirect Command Buffers](https://developer.apple.com/documentation/metal/indirect_command_encoding/encoding_indirect_command_buffers_on_the_gpu)).

### Indirect Render Passes (GPU Driven Rendering)
VimKit provides the ability to perform GPU driven rendering by default on all Apple devices with GPU families of `.apple4` (Apple A11) or greater. If the device supports  *indirect command buffers* (ICB), the render commands are generated on the GPU to maximize parallelization. The following devices support Indirect Command Buffers:

- A Mac from mid-2016 and later with macOS 11 and later
- An iPad with A11 Bionic and later using iPadOS 14.1 and later
- An iOS device with A11 Bionic and later using iOS 14.1 and later

In order to maximize GPU and CPU parallelization, the Indirect Render Pass will dispatch a thread grid size of `width x height` where the width == the maximum number of submeshes a mesh can contain and height == the number of instanced meshes the geometry contains. [Metal automaticaly calculates the number of threadgroups](https://developer.apple.com/documentation/metal/compute_passes/calculating_threadgroup_and_grid_sizes) and provides nonuniform threadgroups if the grid size isn’t a multiple of the threadgroup size.

[Indirect.metal](https://github.com/codefiesta/VimKit/blob/main/Sources/VimKitShaders/Resources/Indirect.metal#L256) and [RenderPass+Indirect.swift](https://github.com/codefiesta/VimKit/blob/main/Sources/VimKit/Renderer/RenderPass%2BIndirect.swift) are the best resources to understand how the kernel code issues rendering instructions on the GPU.

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

