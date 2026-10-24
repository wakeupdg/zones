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

  @Test func marginGapLive() {
    let start = EditorModel.open(columns(), display: primaryKey, topology: topology, assignments: [:])

    let (afterMargin, marginEffects) = step(start, .command(.setMargin(20)))
    #expect(marginEffects.isEmpty)
    #expect(afterMargin.draft.layout.insets.margin == 20)
    #expect(afterMargin.draft.dirty)
    #expect(afterMargin.preview == LayoutMath.resolve(afterMargin.draft.layout, key: primaryKey, visibleFrame: afterMargin.visibleFrame, scale: afterMargin.scale))
    #expect(afterMargin.preview.zones.map(\.frame) != start.preview.zones.map(\.frame))

    let (afterGap, gapEffects) = step(afterMargin, .command(.setGap(12)))
    #expect(gapEffects.isEmpty)
    #expect(afterGap.draft.layout.insets == Insets(margin: 20, gap: 12))
    #expect(afterGap.preview == LayoutMath.resolve(afterGap.draft.layout, key: primaryKey, visibleFrame: afterGap.visibleFrame, scale: afterGap.scale))
    #expect(afterGap.preview.zones.map(\.frame) != afterMargin.preview.zones.map(\.frame))

    let (undone, undoEffects) = step(afterGap, .undo)
    #expect(undoEffects.isEmpty)
    #expect(undone.preview == afterMargin.preview)
    #expect(undone.draft == afterMargin.draft)
    let (redone, redoEffects) = step(undone, .redo)
    #expect(redoEffects.isEmpty)
    #expect(redone.preview == afterGap.preview)
    #expect(redone.draft == afterGap.draft)

    // Nothing to undo or redo is a no-op.
    #expect(step(start, .undo) == (start, []))
    #expect(step(start, .redo) == (start, []))

    // A failing command leaves the state alone and reports the error.
    let (failed, failEffects) = step(start, .command(.merge))
    #expect(failed == start)
    #expect(failEffects == [.error(.nothingSelected)])
  }

  /// Labels the Overlay draws for `layout` freshly resolved on the editor's Display; never reads `state.preview`.
  private func overlayLabels(_ state: EditorState, appearance: Appearance) -> [ZoneLabel] {
    let fresh = LayoutMath.resolve(
      state.draft.layout, key: state.display, visibleFrame: state.visibleFrame, scale: state.scale)
    let scene = OverlayScene(
      layouts: [fresh], appearance: appearance, options: AccessibilityOptions(reduceTransparency: false, reduceMotion: false))
    return OverlayModel.panels(scene).flatMap(\.zones).map(\.label).sorted { $0.number < $1.number }
  }

  private let appearance = Appearance(
    fill: RGBA(r: 0.2, g: 0.4, b: 0.9, a: 1), opacity: 0.5, defaultInsets: Insets(margin: 0, gap: 0))

  @Test func labelsMatchOverlay() {
    var state = EditorModel.open(columns(), display: leftKey, topology: topology, assignments: [:])
    #expect(EditorModel.labels(state, appearance: appearance) == overlayLabels(state, appearance: appearance))
    let events: [EditorEvent] = [
      .command(.select(NodePath(steps: []))), .command(.split(.horizontal)), .command(.split(.vertical)),
      .command(.setGap(12)), .command(.setMargin(20)), .command(.rename("Renamed")), .undo, .redo, .undo, .undo,
    ]
    for (i, event) in events.enumerated() {
      state = step(state, event).0
      let editor = EditorModel.labels(state, appearance: appearance)
      #expect(editor == overlayLabels(state, appearance: appearance), "after step \(i): \(event)")
      #expect(editor.count == state.preview.zones.count, "after step \(i): \(event)")
    }
  }

  @Test func labelsMatchOverlayUnderRandomCommands() {
    for seed in UInt64(1)...5 {
      var g = Generator(seed: seed)
      var state = EditorModel.open(columns(3), display: primaryKey, topology: topology, assignments: [:])
      for i in 0..<50 {
        let event: EditorEvent
        switch g.int(0...7) {
        case 0: event = .command(.select(g.pick(state.preview.zones).path))
        case 1: event = .command(.split(.horizontal))
        case 2: event = .command(.split(.vertical))
        case 3: event = .command(.merge)
        case 4: event = .command(.setGap(Double(g.int(0...30))))
        case 5: event = .command(.setMargin(Double(g.int(0...30))))
        case 6: event = .undo
        default: event = .redo
        }
        state = step(state, event).0
        #expect(
          EditorModel.labels(state, appearance: appearance) == overlayLabels(state, appearance: appearance),
          "seed=\(seed) step=\(i) event=\(event)")
      }
    }
  }
}
