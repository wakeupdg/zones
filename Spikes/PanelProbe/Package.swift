// swift-tools-version: 6.0
import PackageDescription

// Throwaway spike (T03). Standalone: NOT part of the root package or XcodeGen.
let package = Package(
  name: "PanelProbe",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(
      name: "PanelProbe",
      swiftSettings: [.swiftLanguageMode(.v6)]
    )
  ]
)
