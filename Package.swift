// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "OrbitDrop",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OrbitDrop", targets: ["OrbitDrop"])],
    targets: [.executableTarget(name: "OrbitDrop")]
)
