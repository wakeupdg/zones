import Testing
import ZonesCore
import ZonesWindowing

@Suite struct AboutModelTests {
  // AC-029
  @Test func fieldsAndSingleAttributionLine() {
    let bundle = BundleInfo(version: "1.2.3", build: "45", signingIdentity: "ad-hoc", macOS: "15.0")
    let about = AboutModel(bundle: bundle)
    #expect(about.version == "1.2.3")
    #expect(about.build == "45")
    #expect(about.signingIdentity == "ad-hoc")

    let report = Diagnostics.report(
      bundle: bundle, permission: .granted, tap: .alive, topology: nil, assignments: [:],
      prefs: .defaults, ring: EventRing())
    #expect(about.signingIdentity == report.signingIdentity)

    #expect(about.license == "MIT")
    #expect(about.attribution == "inspired by FancyZones")
    #expect(!about.attribution.contains("\n"))
    let joined = [about.version, about.build, about.signingIdentity, about.license, about.attribution]
      .joined(separator: "\n")
    #expect(joined.components(separatedBy: "FancyZones").count - 1 == 1)
  }
}
