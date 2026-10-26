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
  var l = Templates.generate(.columns, count: count, insets: insets)!
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

  @Test func switchDisplayPromptsWhenDirty() {
    let layout = columns(2, insets: Insets(margin: 8, gap: 4))
    let clean = EditorModel.open(layout, display: primaryKey, topology: topology, assignments: [:])
    let other = topology.display(leftKey)!

    // Clean draft: switch and re-resolve.
    let (switched, effects) = step(clean, .switchDisplay(leftKey, confirmed: false))
    #expect(effects.isEmpty)
    #expect(switched.display == leftKey)
    #expect(switched.visibleFrame == other.visibleFrame)
    #expect(switched.scale == other.scale)
    #expect(switched.preview == LayoutMath.resolve(layout, key: leftKey, visibleFrame: other.visibleFrame, scale: other.scale))
    #expect(switched.warnings == EditorEngine.warnings(switched.preview))
    #expect(switched.draft == clean.draft)

    // Dirty draft, not confirmed: unchanged state plus a prompt.
    let (dirty, _) = step(clean, .command(.setGap(10)))
    #expect(dirty.draft.dirty)
    let (kept, prompt) = step(dirty, .switchDisplay(leftKey, confirmed: false))
    #expect(kept == dirty)
    #expect(prompt == [.promptUnsaved(leftKey)])

    // Dirty draft, confirmed: switches, keeps draft and stacks.
    let (forced, forcedEffects) = step(dirty, .switchDisplay(leftKey, confirmed: true))
    #expect(forcedEffects.isEmpty)
    #expect(forced.display == leftKey)
    #expect(forced.draft == dirty.draft)
    #expect(forced.undo == dirty.undo)
    #expect(forced.preview == LayoutMath.resolve(dirty.draft.layout, key: leftKey, visibleFrame: other.visibleFrame, scale: other.scale))

    // A disconnected Display with an Assignment uses its stored geometry.
    let stored = CGRect(x: 0, y: 0, width: 2560, height: 1415)
    let document = ZonesDocument(assignments: [goneUUID: assignment(frame: stored, scale: 2)])
    let (offline, offlineEffects) = step(clean, .switchDisplay(.uuid(goneUUID), confirmed: false), document)
    #expect(offlineEffects.isEmpty)
    #expect(offline.display == .uuid(goneUUID))
    #expect(offline.visibleFrame == stored)
    #expect(offline.scale == 2)
    #expect(offline.preview == LayoutMath.resolve(layout, key: .uuid(goneUUID), visibleFrame: stored, scale: 2))
  }

  @Test func assignWritesOnce() {
    let layout = columns()
    let state = EditorModel.open(layout, display: primaryKey, topology: topology, assignments: [:])
    let primaryUUID = "11111111-1111-4111-8111-111111111111"
    let leftUUID = "22222222-2222-4222-8222-222222222222"

    let (same, effects) = step(state, .assign)
    #expect(effects.count == 1)
    #expect(effects == [.writeAssignment(PersistentDisplayKey(uuid: primaryUUID), layout.id)])
    #expect(same == state)
    #expect(!effects.contains { if case .writeLayouts = $0 { true } else { false } })

    // After a switch the key is the new Display's, and the Layout id is the draft's.
    let (switched, _) = step(state, .switchDisplay(leftKey, confirmed: false))
    let (_, switchedEffects) = step(switched, .assign)
    #expect(switchedEffects.count == 1)
    #expect(switchedEffects == [.writeAssignment(PersistentDisplayKey(uuid: leftUUID), layout.id)])

    // A dirty draft is assigned as it stands: still one effect, still no layouts write.
    let (dirty, _) = step(state, .command(.setGap(6)))
    #expect(step(dirty, .assign).1 == [.writeAssignment(PersistentDisplayKey(uuid: primaryUUID), layout.id)])

    // A disconnected Display is still keyed by its UUID.
    let gone = EditorModel.open(layout, display: .uuid(goneUUID), topology: topology, assignments: [:])
    #expect(step(gone, .assign).1 == [.writeAssignment(PersistentDisplayKey(uuid: goneUUID), layout.id)])

    // An unstable key is never persisted.
    let unstable = EditorModel.open(layout, display: .unstable("session-7"), topology: topology, assignments: [:])
    #expect(step(unstable, .assign).1.isEmpty)
  }

  @Test func saveWritesOnceCancelWritesNothing() throws {
    let layout = columns()
    var state = EditorModel.open(layout, display: primaryKey, topology: topology, assignments: [:])
    for event in [EditorEvent.command(.select(NodePath(steps: [false]))), .command(.split(.vertical)), .command(.setGap(12))] {
      state = step(state, event).0
    }
    #expect(state.draft.dirty)
    let other = Layout(
      id: LayoutID(rawValue: "other"), name: "Other", root: .leaf, surround: Surround(top: 0, left: 0, bottom: 0, right: 0),
      insets: noInsets)
    let before = ZonesDocument(layouts: [other, layout])

    let (saved, effects) = step(state, .save, before)
    #expect(effects.count == 2)
    guard case .writeLayouts(let doc)? = effects.first else {
      Issue.record("first effect is not writeLayouts: \(effects)")
      return
    }
    #expect(effects.last == .replaceLive(state.draft.layout))
    #expect(doc.layouts == [other, state.draft.layout])  // replaced in place, order kept
    #expect(doc.layouts.allSatisfy { $0.builtIn == nil })
    #expect(!saved.draft.dirty)
    #expect(saved.undo.isEmpty && saved.redo.isEmpty)
    #expect(saved.draft.layout == state.draft.layout)
    #expect(saved.preview == state.preview)

    // A new Layout is appended; a built-in draft is saved as a custom Layout.
    var builtIn = state
    builtIn.draft.layout.id = LayoutID(rawValue: "fresh")
    builtIn.draft.layout.builtIn = BuiltInRef(template: .columns, count: 2)
    guard case .writeLayouts(let appended)? = step(builtIn, .save, before).1.first else {
      Issue.record("no writeLayouts for a new Layout")
      return
    }
    #expect(appended.layouts.map(\.id.rawValue) == ["other", "custom-1", "fresh"])
    #expect(appended.layouts.last?.builtIn == nil)

    // The test is the effect interpreter: one atomic write, and the file decodes to the saved document.
    let fs = FakeFileSystem()
    let directory = URL(fileURLWithPath: "/zones-test")
    let store = DocumentStore(fs: fs, directory: directory, clock: FakeClock())
    try store.save(doc, as: .layouts)
    #expect(fs.calls.filter { if case .writeAtomic = $0 { true } else { false } }.count == 1)
    #expect(store.load(.layouts) == .loaded(doc))
    let bytes = try #require(fs.files[directory.appendingPathComponent(DocumentKind.layouts.rawValue)])
    #expect(try JSONDecoder().decode(ZonesDocument.self, from: bytes) == doc)

    // An invalid draft is refused: error effect, no write, state unchanged.
    var invalid = state
    invalid.draft.layout.root = .split(axis: .horizontal, ratio: 1.5, first: .leaf, second: .leaf)
    let (same, invalidEffects) = step(invalid, .save, before)
    #expect(same == invalid)
    #expect(invalidEffects == [.error(.invalidRatio)])
    var tiny = state
    tiny.draft.layout.root = .split(axis: .horizontal, ratio: 0.001, first: .leaf, second: .leaf)
    #expect(step(tiny, .save, before).1 == [.error(.tooSmall)])

    // Cancel writes nothing, and a file system fed nothing by the interpreter has zero writes.
    let quiet = FakeFileSystem()
    let (cancelled, cancelEffects) = step(state, .cancel, before)
    #expect(cancelEffects == [.close])
    #expect(cancelled == state)
    #expect(quiet.calls.isEmpty)
  }

  /// T65 (T28/T30 known issue): an empty name and a surround fault have their own errors, not `invalidRatio`.
  @Test func saveReportsNameAndSurroundFaults() {
    let state = EditorModel.open(columns(), display: primaryKey, topology: topology, assignments: [:])
    var blank = state
    blank.draft.layout.name = "   "
    let (unchanged, blankEffects) = step(blank, .save)
    #expect(blankEffects == [.error(.emptyName)])
    #expect(unchanged == blank)
    var wide = state
    wide.draft.layout.surround = Surround(top: 0.5, left: 0, bottom: 0, right: 0)
    #expect(step(wide, .save).1 == [.error(.surroundOutOfRange)])
    // Overlapping leaves and a bad ratio keep the divider error.
    var overlapping = state
    overlapping.draft.layout.root = .split(axis: .horizontal, ratio: 1.5, first: .leaf, second: .leaf)
    #expect(step(overlapping, .save).1 == [.error(.invalidRatio)])
  }

  /// T65, AC-139 as amended by C15: the editor opens on the assigned built-in (Priority Grid 3 by default) as a
  /// custom copy, Template -> Focus 1 replaces the tree and surround and keeps the draft's name (AC-138), the Zone
  /// is selected, and H, H give exactly three side-by-side Zones.
  @Test func ac139TemplateCopyLoop() throws {
    let insets = Insets(margin: 8, gap: 8)
    let builtIn = try #require(Templates.generate(.priorityGrid, count: 3, insets: insets))
    let copy = Templates.duplicate(builtIn, insets: insets, newID: LayoutID(rawValue: "copy-1"))
    #expect(copy.name == "Priority Grid copy")
    let focusCopy = Templates.duplicate(
      try #require(Templates.generate(.focus, count: 1, insets: insets)), insets: insets,
      newID: LayoutID(rawValue: "copy-2"))
    #expect(focusCopy.name == "Focus copy")

    var state = EditorModel.open(copy, display: primaryKey, topology: topology, assignments: [:])
    (state, _) = step(state, .command(.template(.focus, count: 1)))
    #expect(state.draft.layout.name == "Priority Grid copy")
    #expect(state.draft.layout.root == .leaf)
    #expect(state.draft.layout.surround == Surround(top: 0.2, left: 0.2, bottom: 0.2, right: 0.2))
    #expect(state.draft.selection == nil)

    (state, _) = step(state, .command(.select(NodePath(steps: []))))
    (state, _) = step(state, .command(.split(.horizontal)))
    #expect(leafCount(state.draft.layout.root) == 2)
    (state, _) = step(state, .command(.split(.horizontal)))
    #expect(leafCount(state.draft.layout.root) == 3)
    let (saved, effects) = step(state, .save)
    guard case .writeLayouts(let doc)? = effects.first else {
      Issue.record("save wrote nothing: \(effects)")
      return
    }
    let stored = try #require(doc.layouts.first { $0.id == copy.id })
    #expect(leafCount(stored.root) == 3)
    let zones = saved.preview.zones.sorted { $0.frame.minX < $1.frame.minX }
    #expect(zones.count == 3)
    #expect(zones.allSatisfy { $0.frame.minY == zones[0].frame.minY && $0.frame.height == zones[0].frame.height })
    for (left, right) in zip(zones, zones.dropFirst()) { #expect(left.frame.maxX <= right.frame.minX) }
  }
}
