// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "Switcheroo",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Switcheroo", targets: ["Switcheroo"])],
    targets: [.executableTarget(name: "Switcheroo")]
)
