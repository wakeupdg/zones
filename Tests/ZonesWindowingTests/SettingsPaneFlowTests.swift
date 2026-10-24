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
}
