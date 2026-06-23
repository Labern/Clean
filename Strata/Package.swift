// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Strata",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "StrataCore", path: "Sources/StrataCore"),
        .executableTarget(
            name: "Strata",
            dependencies: ["StrataCore"],
            path: "Sources/Strata"
        ),
    ]
)
