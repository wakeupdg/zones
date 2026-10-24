// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WindowIDProbe",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WindowIDProbe", targets: ["WindowIDProbe"])],
    targets: [
        .executableTarget(
            name: "WindowIDProbe",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
