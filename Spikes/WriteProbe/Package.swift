// swift-tools-version: 6.2
import PackageDescription

// Throwaway spike (T07, SPK-010). Standalone: NOT part of the root package.
let package = Package(
  name: "WriteProbe",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(name: "WriteProbe", path: "Sources/WriteProbe")
  ],
  swiftLanguageModes: [.v6]
)
