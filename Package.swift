// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Snipper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Snipper",
            path: "Sources/Snipper"
        )
    ],
    // Build in Swift 5 language mode — the Carbon hotkey C-callback and AppKit
    // main-actor usage gain nothing from Swift 6 strict concurrency. A 5.9
    // tools-version also lets older toolchains (Xcode 15+) build the project.
    swiftLanguageVersions: [.v5]
)
