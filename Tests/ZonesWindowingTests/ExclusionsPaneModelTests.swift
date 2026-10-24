import Foundation
import Testing
import ZonesWindowing

@Suite struct ExclusionsPaneModelTests {
  /// AC-142
  @Test func bundleIdentifierKeyed() {
    var set: Set<String> = []
    ExclusionsPaneModel.add(bundleID: "com.apple.calculator", to: &set)
    ExclusionsPaneModel.add(bundleID: "com.apple.calculator", to: &set)
    #expect(set == ["com.apple.calculator"])

    // two apps with the same display name give two rows, each carrying its identifier
    let twins: Set<String> = ["com.b.Twin", "com.a.Twin"]
    let twinRows = ExclusionsPaneModel.rows(
      twins, names: ["com.b.Twin": "Twin", "com.a.Twin": "Twin"])
    #expect(
      twinRows == [
        ExclusionsPaneModel.Row(name: "Twin", bundleID: "com.a.Twin"),
        ExclusionsPaneModel.Row(name: "Twin", bundleID: "com.b.Twin"),
      ])

    // a missing name falls back to the identifier; order is name (case-insensitive) then id
    let mixed: Set<String> = ["com.z.unnamed", "com.x.apple", "com.y.Banana"]
    let rows = ExclusionsPaneModel.rows(
      mixed, names: ["com.x.apple": "apple", "com.y.Banana": "Banana", "com.unused": "Zed"])
    #expect(rows.map(\.bundleID) == ["com.x.apple", "com.y.Banana", "com.z.unnamed"])
    #expect(rows.map(\.name) == ["apple", "Banana", "com.z.unnamed"])
    #expect(rows.count == mixed.count)
    #expect(ExclusionsPaneModel.rows([], names: [:]).isEmpty)
  }

  @Test func addFromFileURL() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("zones-t14-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let app = root.appendingPathComponent("Sample.app")
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = [
      "CFBundleIdentifier": "com.example.sample", "CFBundleName": "Sample",
      "CFBundlePackageType": "APPL",
    ]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      .write(to: contents.appendingPathComponent("Info.plist"))

    var set: Set<String> = []
    #expect(ExclusionsPaneModel.bundleID(forAppAt: app) == "com.example.sample")
    #expect(ExclusionsPaneModel.add(appAt: app, to: &set))
    #expect(set == ["com.example.sample"])

    let plain = root.appendingPathComponent("NotAnApp", isDirectory: true)
    try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
    #expect(ExclusionsPaneModel.bundleID(forAppAt: plain) == nil)
    #expect(!ExclusionsPaneModel.add(appAt: plain, to: &set))
    #expect(set == ["com.example.sample"])

    // add from the running-apps list stores the bundle id, not the name
    var running: Set<String> = []
    ExclusionsPaneModel.add(bundleID: "com.apple.calculator", to: &running)
    #expect(running == ["com.apple.calculator"])
  }
}
