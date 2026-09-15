// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DesktopLEDs",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DesktopLEDs", targets: ["DesktopLEDs"])],
    targets: [
        .target(name: "LEDProtocol"),
        .executableTarget(name: "DesktopLEDs", dependencies: ["LEDProtocol"]),
        .testTarget(name: "LEDProtocolTests", dependencies: ["LEDProtocol"])
    ]
)
