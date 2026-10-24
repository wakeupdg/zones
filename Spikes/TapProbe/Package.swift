// swift-tools-version: 6.2
import PackageDescription

// Throwaway spike probe (T04, SPK-003 / SPK-017). Standalone; must not import ZonesCore.
let package = Package(
  name: "TapProbe",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(
      name: "TapProbe",
      swiftSettings: [.treatAllWarnings(as: .error)]
    )
  ]
)
