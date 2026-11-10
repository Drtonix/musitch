// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "musitch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "musitch", path: "Sources/musitch")
    ]
)
