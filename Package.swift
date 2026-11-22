// swift-tools-version:5.9
import PackageDescription

var products: [Product] = [.library(name: "DLiveMIDI", targets: ["DLiveMIDI"])]
var targets: [Target] = [
    // Protocol encoding/decoding + TCP/TLS transport. No UI dependencies.
    .target(name: "DLiveMIDI"),
    .testTarget(name: "DLiveMIDITests", dependencies: ["DLiveMIDI"]),
]

#if os(macOS)
// SwiftUI macOS app (skipped on Linux so the protocol library and tests can run in CI).
products.append(.executable(name: "DLiveRemote", targets: ["DLiveRemote"]))
targets.append(.executableTarget(name: "DLiveRemote", dependencies: ["DLiveMIDI"]))
#endif

let package = Package(
    name: "DLiveRemote",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
