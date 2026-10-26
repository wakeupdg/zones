// swift-tools-version: 6.2
import PackageDescription

// Throwaway spike probe (T08). Standalone: NOT referenced by the root Package.swift.
let package = Package(
  name: "HardwareProbe",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(
      name: "HardwareProbe",
      swiftSettings: [.swiftLanguageMode(.v6), .treatAllWarnings(as: .error)]
    )
  ]
)
