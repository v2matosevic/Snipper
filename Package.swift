// swift-tools-version: 6.0
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
    // The Carbon hotkey C-callback and AppKit main-actor usage are simpler in
    // Swift 5 semantics; strict Swift 6 concurrency buys us nothing here.
    swiftLanguageModes: [.v5]
)
