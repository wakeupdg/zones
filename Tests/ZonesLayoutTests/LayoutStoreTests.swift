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
}
