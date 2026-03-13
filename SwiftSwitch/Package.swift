// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftSwitch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SwiftSwitch",
            path: "Sources/SwiftSwitch"
        )
    ]
)
