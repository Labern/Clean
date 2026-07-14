// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GestureDeck",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "GestureDeck", path: "Sources/GestureDeck")
    ]
)
