// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OpenNotch",
            path: "Sources/OpenNotch",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
