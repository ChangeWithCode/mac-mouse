// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Glide",
    platforms: [.macOS(.v13)],
    products: [
        // Pure logic: physics, curves, recognisers, profile model. No platform
        // frameworks, so it builds and tests anywhere Swift runs.
        .library(name: "GlideCore", targets: ["GlideCore"]),
        // The macOS bindings: event taps, HID, gesture synthesis.
        .library(name: "GlideKit", targets: ["GlideKit"]),
        .executable(name: "Glide", targets: ["Glide"]),
    ],
    targets: [
        .target(
            name: "GlideCore",
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .target(
            name: "GlideKit",
            dependencies: ["GlideCore"],
            swiftSettings: [.enableUpcomingFeature("ExistentialAny")]
        ),
        .executableTarget(
            name: "Glide",
            dependencies: ["GlideCore", "GlideKit"]
        ),
        .testTarget(name: "GlideCoreTests", dependencies: ["GlideCore"]),
    ]
)
