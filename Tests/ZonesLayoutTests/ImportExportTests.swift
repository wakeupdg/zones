import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesTestSupport

@testable import ZonesLayout

private let noSurround = Surround(top: 0, left: 0, bottom: 0, right: 0)
private let twoUp = SplitNode.split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf)
private let keyA = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
private let keyB = "47D8832A-2D66-02CA-B9F7-8F30A301B230"
private let keyC = "57D8832A-2D66-02CA-B9F7-8F30A301B230"

private func custom(_ id: String, _ name: String, root: SplitNode = twoUp) -> Layout {
  Layout(
    id: LayoutID(rawValue: id), name: name, root: root, surround: noSurround, insets: Insets(margin: 3, gap: 5))
}

private func assignment(_ layout: String) -> Assignment {
  Assignment(
    layout: LayoutID(rawValue: layout), displayName: "D", lastVisibleFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
    lastScale: 2, lastSeen: nil)
}

struct ImportExportTests {
  @Test func exportAllAndOne() throws {
    let store = LayoutStore(
      document: ZonesDocument(layouts: [custom("L1", "One"), custom("L2", "Two")]),
      defaults: Insets(margin: 8, gap: 8))
    let assignments = [keyA: assignment("L1"), keyB: assignment("L2"), keyC: assignment("L1")]

    let all = ImportExport.export(store, assignments: assignments, only: nil)
    #expect(all.version == Constants.documentVersion)
    #expect(all.layouts.map(\.id.rawValue) == ["L1", "L2"])
    #expect(all.assignments == assignments)

    let one = ImportExport.export(store, assignments: assignments, only: LayoutID(rawValue: "L1"))
    #expect(one.layouts.map(\.id.rawValue) == ["L1"])
    #expect(Set(one.assignments.keys) == [keyA, keyC])

    let builtIn = ImportExport.export(
      store, assignments: assignments, only: Templates.builtInID(.priorityGrid, count: 3))
    #expect(builtIn.layouts.isEmpty)
    let unknown = ImportExport.export(store, assignments: assignments, only: LayoutID(rawValue: "nope"))
    #expect(unknown.layouts.isEmpty)

    let decoded = try JSONDecoder().decode(ZonesDocument.self, from: all.encoded(for: nil))
    #expect(decoded == all)
  }
}
