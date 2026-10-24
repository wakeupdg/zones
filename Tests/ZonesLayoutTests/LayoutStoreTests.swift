import CoreGraphics
import Foundation
import Testing
import ZonesCore

@testable import ZonesLayout

private let noSurround = Surround(top: 0, left: 0, bottom: 0, right: 0)

private func custom(_ id: String, _ name: String, insets: Insets = Insets(margin: 3, gap: 5)) -> Layout {
  Layout(
    id: LayoutID(rawValue: id), name: name, root: .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf),
    surround: noSurround, insets: insets)
}

private func assignment(_ layout: String, name: String = "D") -> Assignment {
  Assignment(
    layout: LayoutID(rawValue: layout), displayName: name, lastVisibleFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
    lastScale: 2, lastSeen: nil)
}

struct LayoutStoreTests {
  @Test func defaultsApplyToBuiltInsOnly() {
    let mine = custom("C1", "Mine")
    var store = LayoutStore(document: ZonesDocument(layouts: [mine]), defaults: Insets(margin: 8, gap: 8))
    #expect(store.builtIns.map(\.id) == Templates.all(insets: Insets(margin: 8, gap: 8)).map(\.id))
    #expect(store.builtIns.allSatisfy { $0.insets == Insets(margin: 8, gap: 8) })
    #expect(store.custom == [mine])

    store.setDefaults(Insets(margin: 20, gap: 4))
    #expect(store.builtIns.count == 12)
    #expect(store.builtIns.allSatisfy { $0.insets == Insets(margin: 20, gap: 4) })
    #expect(store.custom == [mine])
    #expect(store.document.layouts == [mine])
    #expect(store.document.layouts.allSatisfy { $0.builtIn == nil && !$0.id.rawValue.hasPrefix("builtin:") })
    #expect(store.document.layouts.allSatisfy { $0.insets.margin.isFinite && $0.insets.gap.isFinite })
    #expect(store.document.version == Constants.documentVersion)
    #expect(store.document.assignments.isEmpty)
  }

  @Test func initDropsBuiltInsFromDocument() {
    let builtIn = Templates.generate(.columns, count: 2, insets: Insets(margin: 1, gap: 1))
    let store = LayoutStore(document: ZonesDocument(layouts: [builtIn]), defaults: Insets(margin: 8, gap: 8))
    #expect(store.custom.isEmpty)
    #expect(store.document.layouts.isEmpty)
  }

  @Test func upsertAddsAndReplaces() {
    var store = LayoutStore(
      document: ZonesDocument(layouts: [custom("A", "A"), custom("B", "B")]), defaults: Insets(margin: 8, gap: 8))
    store.upsert(custom("C", "C"))
    #expect(store.custom.map(\.id.rawValue) == ["A", "B", "C"])

    let renamed = custom("B", "B renamed", insets: Insets(margin: 1, gap: 2))
    store.upsert(renamed)
    #expect(store.custom.map(\.id.rawValue) == ["A", "B", "C"])
    #expect(store.layout(LayoutID(rawValue: "B")) == renamed)

    let before = store
    store.upsert(Templates.generate(.rows, count: 2, insets: Insets(margin: 0, gap: 0)))
    var fake = custom("builtin:fake:1", "Fake")
    store.upsert(fake)
    fake = custom("D", "D")
    fake.builtIn = BuiltInRef(template: .grid, count: 4)
    store.upsert(fake)
    #expect(store == before)

    #expect(store.layout(Templates.builtInID(.priorityGrid, count: 3))?.builtIn != nil)
    #expect(store.layout(LayoutID(rawValue: "A"))?.name == "A")
    #expect(store.layout(LayoutID(rawValue: "missing")) == nil)
  }

  @Test func deleteAssignedRequiresReplacement() throws {
    let a = LayoutID(rawValue: "A"), b = LayoutID(rawValue: "B")
    let start = LayoutStore(
      document: ZonesDocument(layouts: [custom("A", "A"), custom("B", "B"), custom("U", "Unused")]),
      defaults: Insets(margin: 8, gap: 8))
    let original: [String: Assignment] = [
      "d1": assignment("A", name: "One"), "d2": assignment("A", name: "Two"), "d3": assignment("B", name: "Three"),
    ]

    var store = start
    var assignments = original
    guard case .failure = store.delete(a, replacement: nil, assignments: &assignments) else {
      Issue.record("delete without replacement should fail")
      return
    }
    #expect(store == start)
    #expect(assignments == original)

    for bad in [a, LayoutID(rawValue: "missing")] {
      guard case .failure = store.delete(a, replacement: bad, assignments: &assignments) else {
        Issue.record("replacement \(bad) should fail")
        return
      }
      #expect(store == start)
      #expect(assignments == original)
    }

    try store.delete(a, replacement: b, assignments: &assignments).get()
    #expect(store.layout(a) == nil)
    #expect(store.custom.map(\.id.rawValue) == ["B", "U"])
    #expect(assignments["d1"]?.layout == b)
    #expect(assignments["d2"]?.layout == b)
    #expect(assignments["d3"] == original["d3"])
    #expect(assignments["d1"]?.displayName == "One")
    #expect(assignments["d2"]?.displayName == "Two")
    #expect(assignments["d1"]?.lastScale == 2)
  }

  @Test func deleteUnassignedAndBuiltInRules() throws {
    var store = LayoutStore(
      document: ZonesDocument(layouts: [custom("U", "Unused"), custom("B", "B")]), defaults: Insets(margin: 8, gap: 8))
    var assignments: [String: Assignment] = ["d": assignment("B")]
    let builtIn = Templates.builtInID(.priorityGrid, count: 3)
    let before = store
    guard case .failure = store.delete(builtIn, replacement: LayoutID(rawValue: "B"), assignments: &assignments) else {
      Issue.record("built-in delete should fail")
      return
    }
    guard case .failure = store.delete(LayoutID(rawValue: "nope"), replacement: nil, assignments: &assignments) else {
      Issue.record("unknown delete should fail")
      return
    }
    #expect(store == before)
    try store.delete(LayoutID(rawValue: "U"), replacement: nil, assignments: &assignments).get()
    #expect(store.custom.map(\.id.rawValue) == ["B"])
    #expect(assignments["d"]?.layout.rawValue == "B")
  }
}
