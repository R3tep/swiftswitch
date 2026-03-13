// swift-tools-version: 5.10
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
