// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Preflight",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Miracle", targets: ["Preflight"])],
    targets: [
        .executableTarget(name: "Preflight", resources: [.copy("Resources/demo-response.json"), .copy("Resources/Demo")]),
        .testTarget(name: "PreflightTests", dependencies: ["Preflight"])
    ]
)
