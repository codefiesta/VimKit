// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VimKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "VimKit",
            targets: ["VimKit"]
        ),
        .library(
            name: "VimKitCompositor",
            targets: ["VimKitCompositor"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms", from: .init(1, 2, 0))
    ],
    targets: [
        .target(
            name: "VimKitShaders",
            resources: [.process("Resources/")]
        ),
        .target(
            name: "VimKit",
            dependencies: [
                "VimKitShaders",
                .product(name: "Algorithms", package: "swift-algorithms")
            ],
            resources: [.process("Resources/")],
            linkerSettings: [
                .linkedFramework("CryptoKit"),
                .linkedFramework("MetalKit")
            ]
        ),
        .target(
            name: "VimKitCompositor",
            dependencies: ["VimKitShaders", "VimKit"],
            linkerSettings: [
                .linkedFramework("CompositorServices", .when(platforms: [.visionOS]))
            ]
        ),
        .testTarget(
            name: "VimKitTests",
            dependencies: ["VimKit"],
            resources: [.copy("Resources/sample.vim")]
        )
    ]
)
