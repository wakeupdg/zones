import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

@testable import ZonesLayout

private let primaryKey = DisplayKey.uuid("11111111-1111-4111-8111-111111111111")
private let leftKey = DisplayKey.uuid("22222222-2222-4222-8222-222222222222")
private let goneUUID = "99999999-9999-4999-8999-999999999999"
private let topology = Fixtures.threeDisplays
private let noInsets = Insets(margin: 0, gap: 0)

private func columns(_ count: Int = 2, insets: Insets = noInsets) -> Layout {
  var l = Templates.generate(.columns, count: count, insets: insets)
  l.id = LayoutID(rawValue: "custom-1")
  l.builtIn = nil
  return l
}

private func context(_ document: ZonesDocument = ZonesDocument()) -> (topology: TopologySnapshot, document: ZonesDocument) {
  (topology, document)
}

private func step(_ s: EditorState, _ e: EditorEvent, _ document: ZonesDocument = ZonesDocument()) -> (EditorState, [EditorEffect]) {
  EditorModel.reduce(s, e, context: context(document))
}

private func assignment(layout: String = "custom-1", frame: CGRect, scale: Double) -> Assignment {
  Assignment(
    layout: LayoutID(rawValue: layout), displayName: "Gone", lastVisibleFrame: frame, lastScale: scale, lastSeen: nil)
}

struct EditorModelTests {
  @Test func disconnectedDisplayUsesStoredGeometry() {
    let layout = columns()
    let stored = CGRect(x: 0, y: 0, width: 2560, height: 1415)
    let state = EditorModel.open(
      layout, display: .uuid(goneUUID), topology: topology,
      assignments: [goneUUID: assignment(frame: stored, scale: 2)])
    #expect(state.display == .uuid(goneUUID))
    #expect(state.visibleFrame == stored)
    #expect(state.scale == 2)
    #expect(state.preview == LayoutMath.resolve(layout, key: .uuid(goneUUID), visibleFrame: stored, scale: 2))
    #expect(state.draft == EditorDraft(layout: layout, selection: nil, dirty: false))
    #expect(state.undo.isEmpty && state.redo.isEmpty)
    #expect(state.warnings == EditorEngine.warnings(state.preview))

    let connected = EditorModel.open(layout, display: primaryKey, topology: topology, assignments: [:])
    let snap = topology.display(primaryKey)!
    #expect(connected.visibleFrame == snap.visibleFrame)
    #expect(connected.scale == snap.scale)
    #expect(connected.preview == LayoutMath.resolve(layout, key: primaryKey, visibleFrame: snap.visibleFrame, scale: snap.scale))
    #expect(connected.preview != state.preview)
  }
}
