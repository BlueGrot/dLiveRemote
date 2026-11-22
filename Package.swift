// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DLiveRemote",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DLiveMIDI", targets: ["DLiveMIDI"]),
        .executable(name: "DLiveRemote", targets: ["DLiveRemote"]),
    ],
    targets: [
        // Protocol encoding/decoding + TCP/TLS transport. No UI dependencies.
        .target(name: "DLiveMIDI"),
        // SwiftUI macOS app.
        .executableTarget(name: "DLiveRemote", dependencies: ["DLiveMIDI"]),
        .testTarget(name: "DLiveMIDITests", dependencies: ["DLiveMIDI"]),
    ]
)
