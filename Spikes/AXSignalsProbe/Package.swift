// swift-tools-version: 6.0
import PackageDescription

// Standalone spike package (T06). Not part of the root Zones package.
let package = Package(
  name: "AXSignalsProbe",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(name: "AXSignalsProbe", path: "Sources/AXSignalsProbe")
  ],
  swiftLanguageModes: [.v6]
)
