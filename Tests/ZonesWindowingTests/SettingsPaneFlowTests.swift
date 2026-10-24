import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

let flowKeyA = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
let flowKeyB = "47D8832A-2D66-02CA-B9F7-8F30A301B230"
let flowKeyC = "57D8832A-2D66-02CA-B9F7-8F30A301B230"
let flowInsets = Insets(margin: 8, gap: 8)
let flowDirectory = URL(fileURLWithPath: "/zones-test")

func flowLayout(_ id: String, _ name: String) -> Layout {
  Layout(
    id: LayoutID(rawValue: id), name: name,
    root: .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf),
    surround: Surround(top: 0, left: 0, bottom: 0, right: 0), insets: Insets(margin: 3, gap: 5))
}

func flowAssignment(_ layout: String, name: String = "D") -> Assignment {
  Assignment(
    layout: LayoutID(rawValue: layout), displayName: name,
    lastVisibleFrame: CGRect(x: 0, y: 0, width: 100, height: 50), lastScale: 2, lastSeen: nil)
}

/// A flow over a fake disk holding two custom Layouts and three Assignments.
func makeFlow(
  layouts: [Layout] = [flowLayout("L1", "One"), flowLayout("L2", "Two")],
  assignments: [String: Assignment]? = nil, fs: FakeFileSystem = FakeFileSystem()
) -> (LayoutsFlow, FakeFileSystem) {
  let documents = DocumentStore(fs: fs, directory: flowDirectory, clock: FakeClock())
  let assignments =
    assignments ?? [flowKeyA: flowAssignment("L1"), flowKeyB: flowAssignment("L2"), flowKeyC: flowAssignment("L1")]
  let flow = LayoutsFlow(
    documents: documents, layouts: ZonesDocument(layouts: layouts), assignments: assignments, defaults: flowInsets)
  return (flow, fs)
}

@Suite struct SettingsPaneFlowTests {
  @Test func exportAllAndOne() throws {
    let (flow, fs) = makeFlow()

    let all = flow.exportDocument(only: nil)
    #expect(all.version == Constants.documentVersion)
    #expect(all.layouts.map(\.id.rawValue) == ["L1", "L2"])
    #expect(all.assignments == flow.assignments)

    let one = flow.exportDocument(only: LayoutID(rawValue: "L1"))
    #expect(one.version == Constants.documentVersion)
    #expect(one.layouts.map(\.id.rawValue) == ["L1"])
    #expect(Set(one.assignments.keys) == [flowKeyA, flowKeyC])

    // The file is the one document codec's bytes.
    let target = URL(fileURLWithPath: "/export/zones-layout.json")
    try flow.writeExport(only: LayoutID(rawValue: "L1"), to: target, fs: fs)
    let written = try #require(fs.files[target])
    #expect(written == (try one.encoded(for: nil)))
    #expect(try JSONDecoder().decode(ZonesDocument.self, from: written) == one)
  }

  // MARK: Import sheet

  private func writes(_ fs: FakeFileSystem) -> [URL] {
    fs.calls.compactMap { if case .writeAtomic(let url, _) = $0 { url } else { nil } }
  }

  private func stored(_ fs: FakeFileSystem, _ name: String) throws -> ZonesDocument {
    let data = try #require(fs.files[flowDirectory.appending(path: name)])
    return try JSONDecoder().decode(ZonesDocument.self, from: data)
  }

  private let incoming = ZonesDocument(
    layouts: [flowLayout("L1", "One"), flowLayout("N9", "Nine")],
    assignments: [flowKeyA: flowAssignment("N9", name: "Dup"), flowKeyB: flowAssignment("N9", name: "Home")])

  private func sequentialIDs() -> () -> LayoutID {
    var issued = 0
    return {
      issued += 1
      return LayoutID(rawValue: "fresh\(issued)")
    }
  }

  @Test func importMergeReplaceSheet() throws {
    // Nothing applies before the person picks a mode.
    let (made, fs) = makeFlow(assignments: [flowKeyC: flowAssignment("L1")])
    var flow = made
    let before = flow
    let applied1 = flow.applyImport(.merge, attached: [], newID: sequentialIDs(), now: 1_792_000_000)
    #expect(!applied1)
    #expect(flow.assignments == before.assignments)
    #expect(writes(fs).isEmpty)

    // Cancel changes nothing.
    flow.beginImport(try incoming.encoded(for: nil), fileName: "mine.json")
    #expect(flow.pendingImport?.fileName == "mine.json")
    #expect(flow.importError == nil)
    flow.cancelImport()
    #expect(flow.pendingImport == nil)
    #expect(flow.store.custom == before.store.custom)
    #expect(writes(fs).isEmpty)

    // Merge keeps existing, renames the incoming duplicate name, and saves both documents.
    flow.beginImport(try incoming.encoded(for: nil), fileName: "mine.json")
    #expect(flow.replaceBackupName(now: 1_792_000_000) != nil)  // the sheet can show it; Merge makes none
    let applied2 = flow.applyImport(.merge, attached: [flowKeyC], newID: sequentialIDs(), now: 1_792_000_000)
    #expect(applied2)
    #expect(flow.pendingImport == nil)
    #expect(flow.store.custom.map(\.name) == ["One", "Two", "One 2", "Nine"])
    #expect(flow.store.custom.map(\.id.rawValue) == ["L1", "L2", "fresh1", "N9"])
    #expect(flow.lastImport?.backup == nil)
    #expect(flow.lastImport?.mode == .merge)
    // Both imported keys are for Displays that are not attached: reported, and kept.
    #expect(flow.lastImport?.dormant == [flowKeyA, flowKeyB])
    #expect(Set(flow.assignments.keys) == [flowKeyA, flowKeyB, flowKeyC])
    #expect(try stored(fs, "layouts.json").layouts == flow.store.custom)
    #expect(try stored(fs, "assignments.json").assignments == flow.assignments)
    #expect(!fs.files.keys.contains { $0.lastPathComponent.hasSuffix(".bak") })
  }

  @Test func importReplaceNamesBackupBeforeWriting() throws {
    let (made, fs) = makeFlow(assignments: [flowKeyC: flowAssignment("L1")])
    var flow = made
    let now: TimeInterval = 1_792_000_000
    let currentBytes = try flow.exportDocument(only: nil).encoded(for: nil)

    flow.beginImport(try incoming.encoded(for: nil), fileName: "mine.json")
    let name = try #require(flow.replaceBackupName(now: now))
    #expect(writes(fs).isEmpty)  // the sheet names it before anything is written
    #expect(name.hasPrefix("zones.") && name.hasSuffix(".bak"))

    let applied3 = flow.applyImport(.replace, attached: [flowKeyA], newID: sequentialIDs(), now: now)
    #expect(applied3)
    #expect(flow.lastImport?.backup == name)
    #expect(fs.files[flowDirectory.appending(path: name)] == currentBytes)
    #expect(flow.store.custom.map(\.name) == ["One", "Nine"])
    #expect(flow.assignments == incoming.assignments)
    #expect(flow.lastImport?.dormant == [flowKeyB])
    #expect(try stored(fs, "layouts.json").layouts == incoming.layouts)
    #expect(try stored(fs, "assignments.json").assignments == incoming.assignments)
    // The backup is written first.
    #expect(writes(fs).first?.lastPathComponent == name)
  }

  @Test func importErrorsInline() throws {
    let (made, fs) = makeFlow()
    var flow = made
    let before = flow.currentDocument

    func refuse(_ data: Data, expecting parts: [String], _ comment: Comment) {
      flow.beginImport(data, fileName: "bad.json")
      #expect(flow.pendingImport == nil, comment)
      let text = flow.importError ?? ""
      for part in parts { #expect(text.contains(part), comment) }
      #expect(flow.currentDocument == before, comment)
      #expect(fs.files.isEmpty, comment)
    }

    // A newer file names both numbers.
    refuse(Data(#"{"version": 9, "layouts": [], "assignments": {}}"#.utf8), expecting: ["9", "\(Constants.documentVersion)"], "newer")

    // The first offending Layout, in document order, is named.
    var badRatio = flowLayout("B1", "Skewed")
    badRatio.root = .split(axis: .horizontal, ratio: 1.5, first: .leaf, second: .leaf)
    var noName = flowLayout("B2", "  ")
    noName.name = "  "
    let invalid = ZonesDocument(layouts: [flowLayout("OK", "Fine"), badRatio, noName])
    refuse(try invalid.encoded(for: nil), expecting: ["Skewed"], "invalid layout")
    #expect(!(flow.importError ?? "").contains("Fine"))

    refuse(Data("not json".utf8), expecting: ["unreadable"], "corrupt")
    refuse(
      Data(#"{"version": 1, "layouts": [], "assignments": {"not-a-uuid": {}}}"#.utf8), expecting: ["not-a-uuid"],
      "non-UUID key")

    // The next successful import clears the error.
    flow.beginImport(try ZonesDocument(layouts: [flowLayout("N1", "Fresh")]).encoded(for: nil), fileName: "ok.json")
    #expect(flow.importError == nil)
    #expect(flow.pendingImport != nil)
  }
}
