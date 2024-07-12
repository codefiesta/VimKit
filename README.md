![Build](https://github.com/codefiesta/VimKit/actions/workflows/swift.yml/badge.svg)
![Xcode 15.4+](https://img.shields.io/badge/Xcode-15.4%2B-gold.svg)
![Swift 5.10+](https://img.shields.io/badge/Swift-5.10%2B-tomato.svg)
![iOS 17.0+](https://img.shields.io/badge/iOS-17.0%2B-crimson.svg)
![visionOS 1.0+](https://img.shields.io/badge/visionOS-1.0%2B-magenta.svg)
![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-skyblue.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-indigo.svg)](https://opensource.org/licenses/MIT)

# VimKit
Swift Package for reading and rendering [VIM](https://www.vimaec.com/) Files.

## VimKit
Provides the core library for reading and rendering VIM files on MacOS and iOS.

### References
*  [https://github.com/vimaec/vim-format](https://github.com/vimaec/vim-format)
*  [https://github.com/vimaec/bfast](https://github.com/vimaec/bfast)
*  [https://github.com/vimaec/g3d](https://github.com/vimaec/g3d)


## VimKitCompositor
Provides the core library for rendering VIM files on VisionOS (Vision Pro) using [CompositorServices](https://developer.apple.com/documentation/compositorservices).

### References
*  [WWDC 2023 - Discover Metal for immersive apps](https://developer.apple.com/videos/play/wwdc2023/10089/)
*  [WWDC 2023 - Meet ARKit for spatial computing](https://developer.apple.com/videos/play/wwdc2023/10082)
*  [Drawing fully immersive content using Metal](https://developer.apple.com/documentation/compositorservices/drawing_fully_immersive_content_using_metal)

## VimKitShaders
C Library that provides types and enums shared between Metal shaders and Swift.


## VisionOS Usage
The following is an example of the simplest usage of rendering a VIM file in VisionOS:

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

