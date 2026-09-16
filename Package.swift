// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DesktopLEDs",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DesktopLEDs", targets: ["DesktopLEDs"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "LEDProtocol"),
        .executableTarget(
            name: "DesktopLEDs",
            dependencies: ["LEDProtocol", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "LEDProtocolTests", dependencies: ["LEDProtocol"])
    ]
)
