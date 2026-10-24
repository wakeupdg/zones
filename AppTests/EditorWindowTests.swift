import AppKit
import Testing
import Foundation
import ZonesCore
import ZonesLayout
import ZonesWindowing

@testable import Zones

@MainActor
@Suite struct EditorWindowTests {
  static func display(
    key: String = "D1", frame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900),
    visible: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 875)
  ) -> DisplaySnapshot {
    DisplaySnapshot(
      key: .uuid(key), frame: frame, visibleFrame: visible, scale: 2, isMain: true, mirrorOf: nil,
      name: "Built-in", resolution: CGSize(width: 2880, height: 1800))
  }

  @Test func defaultFrameEqualsVisibleFrame() {
    let snapshot = Self.display()  // visibleFrame is inset by a 25 pt menu bar
    let window = EditorWindowController.makeWindow(display: snapshot)
    #expect(window.frame == WindowPlacement.editorFrame(cursor: snapshot))
    #expect(window.frame == snapshot.visibleFrame)
    #expect(window.styleMask.contains(.resizable))
    #expect(!window.isOpaque)
  }

  // MARK: key map

  private static let cmd: NSEvent.ModifierFlags = .command
  private static let cmdShift: NSEvent.ModifierFlags = [.command, .shift]

  @Test func keyEquivalentsMapToEvents() {
    let table: [(String, NSEvent.ModifierFlags, EditorEvent?)] = [
      ("h", [], .command(.split(.horizontal))),
      ("v", [], .command(.split(.vertical))),
      ("m", [], .command(.merge)),
      ("z", Self.cmd, .undo),
      ("z", Self.cmdShift, .redo),
      ("s", Self.cmd, .save),
      ("w", Self.cmd, .cancel),
      ("a", Self.cmdShift, .assign),
      // Command combos must not fire the bare-letter commands.
      ("h", Self.cmd, nil), ("v", Self.cmd, nil), ("m", Self.cmd, nil),
      ("h", .control, nil), ("h", .option, nil), ("h", .shift, nil),
      // Unmapped.
      ("q", [], nil), ("a", Self.cmd, nil), ("a", [], nil), ("s", [], nil), ("z", [], nil),
      ("w", [], nil), ("w", Self.cmdShift, nil), ("s", Self.cmdShift, nil),
    ]
    for (chars, flags, expected) in table {
      let got = EditorKeyMap.event(characters: chars, keyCode: 0, modifiers: flags, selection: nil)
      #expect(got == expected, "\(chars) \(flags) -> \(String(describing: got))")
    }
    // Caps lock and the device-dependent bits AppKit adds must not break a mapping.
    #expect(
      EditorKeyMap.event(characters: "h", keyCode: 4, modifiers: .capsLock, selection: nil)
        == .command(.split(.horizontal)))
    let commandCaps: NSEvent.ModifierFlags = [.command, .capsLock]
    let saved = EditorKeyMap.event(characters: "S", keyCode: 1, modifiers: commandCaps, selection: nil)
    #expect(saved == .save)
  }

  @Test func arrowKeysNudgeSelectedDivider() {
    let path = NodePath(steps: [false, true])
    // keyCode: 123 left, 124 right, 125 down, 126 up. Left/Up shrink the first child (-), Right/Down grow it (+).
    let table: [(UInt16, NSEvent.ModifierFlags, Double?)] = [
      (123, [], -1), (126, [], -1), (124, [], 1), (125, [], 1),
      (123, .shift, -10), (126, .shift, -10), (124, .shift, 10), (125, .shift, 10),
      // AppKit adds .function and .numericPad to arrow events; they must not matter.
      (124, [.function, .numericPad], 1), (123, [.function, .numericPad, .shift], -10),
      // Other modifiers are not nudges.
      (124, .command, nil), (124, .option, nil), (124, .control, nil),
      // Not an arrow.
      (0, [], nil),
    ]
    for (code, flags, points) in table {
      let got = EditorKeyMap.event(characters: "", keyCode: code, modifiers: flags, selection: path)
      let expected = points.map { EditorEvent.command(.nudge(path, points: $0)) }
      #expect(got == expected, "keyCode \(code) \(flags) -> \(String(describing: got))")
    }
    // No selection: no event.
    for code: UInt16 in [123, 124, 125, 126] {
      #expect(EditorKeyMap.event(characters: "", keyCode: code, modifiers: [], selection: nil) == nil)
    }
  }

  // MARK: effect routing

  private static let uuidA = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
  private static let uuidB = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"

  static func topology() -> TopologySnapshot {
    let a = display(key: uuidA)
    let bFrame = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    let b = DisplaySnapshot(
      key: .uuid(uuidB), frame: bFrame, visibleFrame: bFrame, scale: 1, isMain: false, mirrorOf: nil,
      name: "Side", resolution: CGSize(width: 1920, height: 1080))
    return TopologySnapshot(displays: [a, b], separateSpaces: true, primaryFrame: a.frame)
  }

  static func blankLayout() -> Layout {
    Layout(
      id: LayoutID(rawValue: "11111111-1111-4111-8111-111111111111"), name: "Mine", root: .leaf,
      surround: Surround(top: 0, left: 0, bottom: 0, right: 0), insets: Insets(margin: 0, gap: 0))
  }

  final class MemoryFileSystem: FileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [URL: Data] = [:]
    func read(_ url: URL) throws -> Data {
      lock.lock()
      defer { lock.unlock() }
      guard let data = files[url] else { throw CocoaError(.fileNoSuchFile) }
      return data
    }
    func writeAtomic(_ data: Data, to url: URL) throws {
      lock.lock()
      defer { lock.unlock() }
      files[url] = data
    }
    func move(_ from: URL, to: URL) throws {
      lock.lock()
      defer { lock.unlock() }
      files[to] = files.removeValue(forKey: from)
    }
    func exists(_ url: URL) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      return files[url] != nil
    }
    func remove(_ url: URL) throws {
      lock.lock()
      defer { lock.unlock() }
      files[url] = nil
    }
  }

  struct StubClock: ZonesCore.Clock {
    var now: TimeInterval { 0 }
    func schedule(_ id: TimerID, after seconds: TimeInterval, repeats: Bool, _ fire: @Sendable @escaping () -> Void)
      -> TimerHandle
    { TimerHandle(id: id, token: 0) }
    func cancel(_ handle: TimerHandle) {}
  }

  @MainActor final class RecordingSink: EditorEffectSink {
    var prompts: [DisplayKey] = []
    var messages: [String] = []
    var closes = 0
    func showUnsavedPrompt(switchingTo key: DisplayKey) { prompts.append(key) }
    func showMessage(_ text: String) { messages.append(text) }
    func closeEditor() { closes += 1 }
  }

  @Test func effectsRouteToStores() throws {
    let fs = MemoryFileSystem()
    let directory = URL(filePath: "/zones-test")
    let store = DocumentStore(fs: fs, directory: directory, clock: StubClock())
    let sink = RecordingSink()
    var live = LayoutStore(document: ZonesDocument(), defaults: Insets(margin: 0, gap: 0))
    let topology = Self.topology()
    let router = EditorWindowTestsRouter.make(store: store, sink: sink, topology: topology) { live.upsert($0) }

    var document = ZonesDocument()
    var state = EditorModel.open(Self.blankLayout(), display: .uuid(Self.uuidA), topology: topology, assignments: [:])
    func send(_ event: EditorEvent) {
      let (next, effects) = EditorModel.reduce(state, event, context: (topology, document))
      state = next
      document = router.route(effects, document: document)
    }

    // Dirty the draft with real reducer output: select the single Zone, split it side by side.
    send(.command(.select(NodePath(steps: []))))
    send(.command(.split(.horizontal)))
    #expect(state.draft.dirty)
    #expect(live.layout(state.draft.layout.id) == nil)  // nothing live before Save

    // promptUnsaved: switching Display on a dirty draft prompts, writes nothing.
    send(.switchDisplay(.uuid(Self.uuidB), confirmed: false))
    #expect(sink.prompts == [.uuid(Self.uuidB)])
    #expect(!fs.exists(directory.appending(path: "layouts.json")))

    // error: merging at the root is refused and surfaced as an inline message.
    send(.command(.select(NodePath(steps: []))))
    send(.command(.merge))
    #expect(sink.messages.count == 1)

    // writeLayouts + replaceLive: Save is the only moment the live Layout changes.
    send(.save)
    let saved = try JSONDecoder().decode(
      ZonesDocument.self, from: fs.read(directory.appending(path: "layouts.json")))
    #expect(saved.layouts.map(\.id) == [state.draft.layout.id])
    #expect(live.layout(state.draft.layout.id) == state.draft.layout)
    #expect(document.layouts.count == 1)

    // writeAssignment: Assign writes assignments.json for the current Display, keeping its stored geometry.
    send(.assign)
    let assigned = try JSONDecoder().decode(
      ZonesDocument.self, from: fs.read(directory.appending(path: "assignments.json")))
    let record = try #require(assigned.assignments[Self.uuidA])
    #expect(record.layout == state.draft.layout.id)
    #expect(record.displayName == "Built-in")
    #expect(record.lastVisibleFrame == CGRect(x: 0, y: 0, width: 1440, height: 875))
    #expect(document.assignments[Self.uuidA]?.layout == record.layout)  // dates lose sub-seconds on disk

    // close
    send(.cancel)
    #expect(sink.closes == 1)
  }

  // MARK: canvas geometry

  @Test func zoneRectsEqualResolvedFrames() {
    let visible = CGRect(x: 100, y: 50, width: 1440, height: 875)
    let insets = Insets(margin: 12, gap: 8)
    let layouts: [Layout] = [
      Templates.generate(.grid, count: 4, insets: insets),
      Templates.generate(.priorityGrid, count: 3, insets: insets),
      Templates.generate(.focus, count: 1, insets: insets),  // surround 0.2
    ]
    for layout in layouts {
      let state = EditorModel.open(
        layout, display: .uuid(Self.uuidA),
        topology: TopologySnapshot(
          displays: [Self.display(key: Self.uuidA, frame: visible, visible: visible)], separateSpaces: true,
          primaryFrame: visible),
        assignments: [:])
      let truth = LayoutMath.resolve(layout, key: .uuid(Self.uuidA), visibleFrame: visible, scale: 2)
      #expect(state.preview == truth)

      // Origin zero: identical frames, in order, with number and path preserved.
      let identity = EditorCanvasGeometry.zoneRects(preview: state.preview, contentOrigin: .zero)
      #expect(identity.map(\.rect) == truth.zones.map(\.frame))
      #expect(identity.map(\.number) == truth.zones.map(\.number))
      #expect(identity.map(\.path) == truth.zones.map(\.path))

      // Origin at the visible frame's corner: shifted by exactly that and nothing else (real scale).
      let local = EditorCanvasGeometry.zoneRects(preview: state.preview, contentOrigin: visible.origin)
      for (zone, rect) in zip(truth.zones, local) {
        #expect(rect.rect == zone.frame.offsetBy(dx: -visible.minX, dy: -visible.minY))
        #expect(rect.rect.size == zone.frame.size)
      }
      // Zone 1 edges equal the Overlay's (LayoutMath.resolve) once the origin is added back.
      let first = local[0].rect
      let zone1 = truth.zones[0].frame
      #expect(first.minX + visible.minX == zone1.minX && first.maxX + visible.minX == zone1.maxX)
      #expect(first.minY + visible.minY == zone1.minY && first.maxY + visible.minY == zone1.maxY)
    }
  }

  @Test func dividerDragProducesSetRatio() throws {
    let visible = CGRect(x: 100, y: 50, width: 1000, height: 500)
    let layout = Layout(
      id: LayoutID(rawValue: "22222222-2222-4222-8222-222222222222"), name: "Mixed",
      root: .split(
        axis: .horizontal, ratio: 0.5, first: .leaf,
        second: .split(axis: .vertical, ratio: 0.5, first: .leaf, second: .leaf)),
      surround: Surround(top: 0, left: 0, bottom: 0, right: 0), insets: Insets(margin: 0, gap: 0))
    let preview = LayoutMath.resolve(layout, key: .uuid(Self.uuidA), visibleFrame: visible, scale: 1)
    let origin = visible.origin
    let dividers = EditorCanvasGeometry.dividers(layout: layout, preview: preview, contentOrigin: origin)
    #expect(dividers.map(\.path) == [NodePath(steps: []), NodePath(steps: [true])])

    // Root divider: side by side, parent is the whole Layout rectangle in view space.
    let root = try #require(dividers.first { $0.path.steps.isEmpty })
    #expect(root.axis == .horizontal)
    #expect(root.parent == CGRect(x: 0, y: 0, width: 1000, height: 500))
    #expect(root.line.midX == 500)

    // Pointer at x = 250 of 1000: ratio 0.25, snapping on by default, off with Option.
    let drag = CGPoint(x: 250, y: 300)
    #expect(
      EditorCanvasGeometry.event(forDragOf: root, to: drag, optionHeld: false)
        == .command(.setRatio(root.path, 0.25, snap: true)))
    #expect(
      EditorCanvasGeometry.event(forDragOf: root, to: drag, optionHeld: true)
        == .command(.setRatio(root.path, 0.25, snap: false)))

    // Nested stacked divider: parent is the right half; first = top, so a pointer 3/4 of the way up is ratio 0.25.
    let nested = try #require(dividers.first { $0.path.steps == [true] })
    #expect(nested.axis == .vertical)
    #expect(nested.parent == CGRect(x: 500, y: 0, width: 500, height: 500))
    #expect(nested.line.midY == 250)
    #expect(
      EditorCanvasGeometry.event(forDragOf: nested, to: CGPoint(x: 800, y: 375), optionHeld: false)
        == .command(.setRatio(nested.path, 0.25, snap: true)))
    // Bottom of the parent is ratio 1 (the reducer owns the refusal, the view does not clamp).
    #expect(
      EditorCanvasGeometry.event(forDragOf: nested, to: CGPoint(x: 800, y: 0), optionHeld: false)
        == .command(.setRatio(nested.path, 1, snap: true)))
  }

  // MARK: toolbar model

  @Test func displaySwitcherListsDisconnectedAndPrompts() throws {
    let topology = Self.topology()
    let gone = "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC"
    let alsoGone = "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD"
    func record(_ name: String) -> Assignment {
      Assignment(
        layout: Self.blankLayout().id, displayName: name, lastVisibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
        lastScale: 1, lastSeen: nil)
    }
    let assignments = [
      Self.uuidA: record("stale name for A"),  // connected: the live snapshot name wins, no duplicate row
      gone: record("Studio Display"), alsoGone: record("Dell"),
    ]
    let choices = EditorToolbarModel.displayChoices(topology: topology, assignments: assignments)
    #expect(
      choices == [
        .init(key: .uuid(Self.uuidA), name: "Built-in", isConnected: true),
        .init(key: .uuid(Self.uuidB), name: "Side", isConnected: true),
        .init(key: .uuid(alsoGone), name: "Dell", isConnected: false),
        .init(key: .uuid(gone), name: "Studio Display", isConnected: false),
      ])

    // Dirty draft: picking prompts and leaves the Display alone; confirming switches (to stored geometry for a
    // disconnected Display, AC-125) and clears nothing else.
    let document = ZonesDocument(assignments: assignments)
    let context = (topology: topology, document: document)
    var state = EditorModel.open(
      Self.blankLayout(), display: .uuid(Self.uuidA), topology: topology, assignments: assignments)
    state = EditorModel.reduce(state, .command(.select(NodePath(steps: []))), context: context).0
    state = EditorModel.reduce(state, .command(.split(.horizontal)), context: context).0
    #expect(state.draft.dirty)

    let target = DisplayKey.uuid(gone)
    let (afterPick, pickEffects) = EditorModel.reduce(state, EditorToolbarModel.pickDisplay(target), context: context)
    #expect(pickEffects == [.promptUnsaved(target)])
    #expect(afterPick.display == .uuid(Self.uuidA))

    #expect(EditorToolbarModel.confirmSwitch(to: target) == .switchDisplay(target, confirmed: true))
    let (switched, confirmEffects) = EditorModel.reduce(
      afterPick, EditorToolbarModel.confirmSwitch(to: target), context: context)
    #expect(confirmEffects.isEmpty)
    #expect(switched.display == target)
    #expect(switched.visibleFrame == CGRect(x: 0, y: 0, width: 800, height: 600))
    #expect(switched.draft == state.draft)

    // Clean draft: no prompt, the switch happens straight away.
    let clean = EditorModel.open(
      Self.blankLayout(), display: .uuid(Self.uuidA), topology: topology, assignments: assignments)
    let (direct, directEffects) = EditorModel.reduce(clean, EditorToolbarModel.pickDisplay(target), context: context)
    #expect(directEffects.isEmpty)
    #expect(direct.display == target)
  }
}

/// Test-only factory so the test reads top-down.
@MainActor
enum EditorWindowTestsRouter {
  static func make(
    store: DocumentStore, sink: EditorWindowTests.RecordingSink, topology: TopologySnapshot,
    upsert: @escaping (Layout) -> Void
  ) -> EditorEffectRouter {
    EditorEffectRouter(store: store, sink: sink, topology: { topology }, upsertLive: upsert)
  }
}
