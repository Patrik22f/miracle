// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Preflight",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Preflight", targets: ["Preflight"])],
    targets: [
        .executableTarget(name: "Preflight", resources: [.copy("Resources/demo-response.json")], linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "PreflightTests", dependencies: ["Preflight"])
    ]
)
