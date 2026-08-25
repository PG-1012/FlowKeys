// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlowKeys",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FlowKeys", targets: ["FlowKeysApp"]),
        .library(name: "FlowKeysCore", targets: ["FlowKeysCore"]),
    ],
    targets: [
        // Pure logic: history, cycling state machine, preferences.
        // No AppKit, so it runs under `swift test` with no permissions.
        .target(name: "FlowKeysCore"),

        // The macOS app: event tap, overlay, paste engine, menu bar.
        .executableTarget(
            name: "FlowKeysApp",
            dependencies: ["FlowKeysCore"]
        ),

        .testTarget(
            name: "FlowKeysCoreTests",
            dependencies: ["FlowKeysCore"]
        ),
    ]
)
