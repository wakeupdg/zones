// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
  name: "Zones",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "ZonesCore", targets: ["ZonesCore"]),
    .library(name: "ZonesLayout", targets: ["ZonesLayout"]),
    .library(name: "ZonesWindowing", targets: ["ZonesWindowing"]),
    .library(name: "ZonesTestSupport", targets: ["ZonesTestSupport"]),
  ],
  targets: [
    .target(name: "ZonesCore", swiftSettings: strict),
    .target(name: "ZonesLayout", dependencies: ["ZonesCore"], swiftSettings: strict),
    .target(name: "ZonesWindowing", dependencies: ["ZonesCore", "ZonesLayout"], swiftSettings: strict),
    .target(
      name: "ZonesTestSupport",
      dependencies: ["ZonesCore", "ZonesLayout", "ZonesWindowing"],
      swiftSettings: strict),
    .testTarget(
      name: "ZonesCoreTests", dependencies: ["ZonesCore", "ZonesTestSupport"], swiftSettings: strict),
    .testTarget(
      name: "ZonesLayoutTests", dependencies: ["ZonesLayout", "ZonesCore", "ZonesTestSupport"],
      swiftSettings: strict),
    .testTarget(
      name: "ZonesWindowingTests",
      dependencies: ["ZonesWindowing", "ZonesCore", "ZonesTestSupport"], swiftSettings: strict),
  ],
  swiftLanguageModes: [.v6]
)
