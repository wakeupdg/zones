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

  @Test func mergeAndReplace() throws {
    let idI = LayoutID(rawValue: "I")
    let current = ZonesDocument(layouts: [custom("I", "Desk")], assignments: [keyA: assignment("I")])
    let incoming = ZonesDocument(
      layouts: [custom("N1", "Desk"), custom("I", "Other"), custom("N2", "Desk")],
      assignments: [keyA: assignment("N1"), keyB: assignment("I"), keyC: assignment("N1")])
    var issued = 0
    let fresh: () -> LayoutID = {
      issued += 1
      return LayoutID(rawValue: "fresh\(issued)")
    }

    let merged = ImportExport.importDocument(
      incoming, into: current, mode: .merge, attached: [keyA], newID: fresh, now: 1_792_000_000)
    guard case .applied(let doc, let backup, let dormant) = merged else {
      Issue.record("merge should apply")
      return
    }
    #expect(backup == nil)
    #expect(doc.version == Constants.documentVersion)
    #expect(doc.layouts.first == current.layouts[0])
    #expect(doc.layouts.map(\.id.rawValue) == ["I", "N1", "fresh1", "N2"])
    #expect(doc.layouts.map(\.name) == ["Desk", "Desk 2", "Other", "Desk 3"])
    #expect(issued == 1)
    #expect(doc.assignments[keyA]?.layout == idI)
    #expect(doc.assignments[keyB]?.layout.rawValue == "fresh1")
    #expect(doc.assignments[keyC]?.layout.rawValue == "N1")
    #expect(dormant == [keyB, keyC])

    // A key that is attached is not dormant.
    guard
      case .applied(_, _, let none) = ImportExport.importDocument(
        incoming, into: current, mode: .merge, attached: [keyA, keyB, keyC], newID: fresh, now: 0)
    else {
      Issue.record("merge should apply")
      return
    }
    #expect(none.isEmpty)

    // Replace: incoming wins whole; the backup name carries the same stamp DocumentStore uses.
    let fs = FakeFileSystem()
    let dir = URL(filePath: "/zones")
    let store = DocumentStore(fs: fs, directory: dir, clock: FakeClock())
    try store.save(ZonesDocument(layouts: current.layouts), as: .layouts)
    try store.save(ZonesDocument(assignments: current.assignments), as: .assignments)
    let oldLayouts = try #require(fs.files[dir.appending(path: "layouts.json")])
    let oldAssignments = try #require(fs.files[dir.appending(path: "assignments.json")])

    let now: TimeInterval = 1_792_000_000
    let replaced = ImportExport.importDocument(
      incoming, into: current, mode: .replace, attached: [keyA], newID: fresh, now: now)
    guard case .applied(let swapped, let backupName?, let dormantAfter) = replaced else {
      Issue.record("replace should apply with a backup")
      return
    }
    #expect(swapped == incoming)
    #expect(dormantAfter == [keyB, keyC])
    let stamp = store.backupName(.layouts, now: now).dropFirst("layouts.".count).dropLast(".bak".count)
    #expect(backupName.contains(stamp))
    #expect(stamp.count == "yyyyMMdd-HHmmss".count)

    // The caller writes both backups, then swaps both documents.
    try fs.writeAtomic(oldLayouts, to: dir.appending(path: store.backupName(.layouts, now: now)))
    try fs.writeAtomic(oldAssignments, to: dir.appending(path: store.backupName(.assignments, now: now)))
    try store.save(ZonesDocument(layouts: swapped.layouts), as: .layouts)
    try store.save(ZonesDocument(assignments: swapped.assignments), as: .assignments)

    let writes = fs.calls.compactMap { call -> String? in
      if case .writeAtomic(let url, _) = call { url.lastPathComponent } else { nil }
    }
    let backupAt = try #require(writes.firstIndex { $0.hasSuffix(".bak") })
    #expect(writes.lastIndex { $0.hasSuffix(".bak") }! < writes.lastIndex(of: "layouts.json")!)
    #expect(backupAt >= 2)
    #expect(fs.files[dir.appending(path: store.backupName(.layouts, now: now))] == oldLayouts)
    #expect(fs.files[dir.appending(path: store.backupName(.assignments, now: now))] == oldAssignments)
    guard case .loaded(let layoutsDoc) = store.load(.layouts), case .loaded(let assignmentsDoc) = store.load(.assignments)
    else {
      Issue.record("both documents should load")
      return
    }
    #expect(layoutsDoc.layouts == incoming.layouts)
    #expect(assignmentsDoc.assignments == incoming.assignments)
  }
}
