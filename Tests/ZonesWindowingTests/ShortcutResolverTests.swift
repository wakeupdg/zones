import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport

@testable import ZonesWindowing

@Suite(.serialized) struct ShortcutResolverTests {
  typealias F = ShortcutFixtures

  static let columns2 = Templates.builtInID(.columns, count: 2)
  static let grid4 = Templates.builtInID(.grid, count: 4)

  /// AC-098: the target Display is the one the window overlaps most, and the Zones are its own Assignment's.
  @Test func sendToZoneUsesOccupiedDisplay() throws {
    let layouts = F.layouts(a: Self.columns2, b: Self.grid4)
    let layoutA = try #require(layouts[F.displayA]), layoutB = try #require(layouts[F.displayB])
    #expect(layoutA.zones.count == 2 && layoutB.zones.count == 4)

    // Mostly on B, with a sliver on A.
    let onB = F.focused(frame: CGRect(x: 1900, y: 200, width: 600, height: 400))
    for mode in [SnapMode.full, .positionOnly] {
      let plan = ShortcutResolver.plan(
        .sendToZone(3), focused: onB, verdict: .allow(mode), topology: F.topology, layouts: layouts,
        registry: OriginalFrameRegistry())
      guard case .snap(let snap) = plan else {
        Issue.record("expected a snap plan, got \(plan)")
        continue
      }
      #expect(snap.display == F.displayB)
      #expect(snap.zones == [3])
      #expect(snap.target == layoutB.zones[2].frame)
      #expect(snap.via == .keyboard)
      #expect(snap.originalFrame == onB.frame)
      #expect(snap.mode == mode)
      #expect(snap.window == onB.record.ref)
    }

    // The same window moved onto A: A's Zone 2 (Zone 3 does not exist on a 2-Zone Layout).
    let onA = F.focused(frame: CGRect(x: 100, y: 200, width: 600, height: 400))
    let planA = ShortcutResolver.plan(
      .sendToZone(2), focused: onA, verdict: .allow(.full), topology: F.topology, layouts: layouts,
      registry: OriginalFrameRegistry())
    guard case .snap(let snapA) = planA else {
      Issue.record("expected a snap plan, got \(planA)")
      return
    }
    #expect(snapA.display == F.displayA)
    #expect(snapA.zones == [2])
    #expect(snapA.target == layoutA.zones[1].frame)
  }

  /// Installs a fresh `ArrayLogSink` on `Log.shared` (global, so the suite is serialized) and returns it.
  static func installSink() -> ArrayLogSink {
    let sink = ArrayLogSink()
    Log.shared.install(sink: sink)
    return sink
  }

  /// AC-101: Zone N beyond the count is a no-op with exactly one log line and no registry change.
  @Test func absentZoneIsNoOp() {
    let sink = Self.installSink()
    defer { sink.reset() }
    let layouts = F.layouts(a: Templates.builtInID(.columns, count: 3), b: Self.grid4)
    let win = F.focused(frame: CGRect(x: 100, y: 200, width: 600, height: 400))
    var registry = OriginalFrameRegistry()
    registry.recordSnap(LastSnapRecord(key: win.record.handle.key, display: F.displayA, zones: [1], frame: win.frame))
    _ = registry.capture(OriginalFrameEntry(key: win.record.handle.key, frame: win.frame, via: .keyboard))
    let before = registry
    for n in [7, 0, -1] {
      sink.reset()
      let plan = ShortcutResolver.plan(
        .sendToZone(n), focused: win, verdict: .allow(.full), topology: F.topology, layouts: layouts,
        registry: registry)
      #expect(plan == .noOp(.zoneAbsent))
      #expect(sink.events.count == 1)
      #expect(sink.events.first?.category == .shortcuts)
      #expect(registry == before)
    }
  }

  // MARK: AC-108 gates

  struct GateCase: Sendable, CustomTestStringConvertible {
    var name: String
    var windowPresent: Bool
    var facts: WindowFacts
    var verdict: Verdict
    var expected: NoOpReason
    var testDescription: String { name }
  }

  static let gateCases: [GateCase] = {
    var cases = [
      GateCase(name: "focused nil", windowPresent: false, facts: F.facts(), verdict: .allow(.full), expected: .windowAbsent),
      GateCase(
        name: "facts full-screen with allow", windowPresent: true, facts: F.facts(fullScreen: true),
        verdict: .allow(.full), expected: .fullScreen),
      GateCase(
        name: "facts position not settable with allow", windowPresent: true, facts: F.facts(positionSettable: false),
        verdict: .allow(.positionOnly), expected: .positionNotSettable),
    ]
    for reason in SkipReason.allCases {
      let expected: NoOpReason =
        switch reason {
        case .fullScreen: .fullScreen
        case .positionNotSettable: .positionNotSettable
        default: .excluded
        }
      cases.append(
        GateCase(
          name: "skip \(reason.rawValue)", windowPresent: true, facts: F.facts(), verdict: .skip(reason),
          expected: expected))
    }
    return cases
  }()

  static let gateActions: [ShortcutAction] = [.sendToZone(1), .cycleRight, .restore]

  @Test("gate table", arguments: gateCases, gateActions)
  func gateTable(_ c: GateCase, _ action: ShortcutAction) {
    let sink = Self.installSink()
    defer { sink.reset() }
    let layouts = F.layouts(a: Self.columns2, b: Self.grid4)
    let win = F.focused(frame: CGRect(x: 100, y: 200, width: 600, height: 400), facts: c.facts)
    var registry = OriginalFrameRegistry()
    _ = registry.capture(OriginalFrameEntry(key: win.record.handle.key, frame: win.frame, via: .keyboard))
    let before = registry
    let plan = ShortcutResolver.plan(
      action, focused: c.windowPresent ? win : nil, verdict: c.verdict, topology: F.topology, layouts: layouts,
      registry: registry)
    #expect(plan == .noOp(c.expected))
    #expect(sink.events.count == 1)
    #expect(sink.events.first?.category == .shortcuts)
    #expect(registry == before)
  }

  // MARK: cycle and restore plans

  static let columns4 = Templates.builtInID(.columns, count: 4)

  func cycle(
    _ action: ShortcutAction, frame: CGRect, record: ((WindowKey) -> LastSnapRecord)? = nil
  ) throws -> (SnapPlan, ResolvedLayout) {
    let layouts = F.layouts(a: Self.columns4, b: Self.grid4)
    let win = F.focused(frame: frame)
    var registry = OriginalFrameRegistry()
    if let record { registry.recordSnap(record(win.record.handle.key)) }
    let plan = ShortcutResolver.plan(
      action, focused: win, verdict: .allow(.full), topology: F.topology, layouts: layouts, registry: registry)
    guard case .snap(let snap) = plan else {
      Issue.record("expected a snap plan, got \(plan)")
      throw CancellationError()
    }
    return (snap, try #require(layouts[F.displayA]))
  }

  @Test func cyclePlansAndRestore() throws {
    let z = F.resolved(.columns, count: 4).zones.map(\.frame)

    // A matching record: Right goes after Zone 1, Left wraps to the last Zone.
    let rec1: (WindowKey) -> LastSnapRecord = { LastSnapRecord(key: $0, display: F.displayA, zones: [1], frame: z[0]) }
    let (right, layout) = try cycle(.cycleRight, frame: z[0], record: rec1)
    #expect(right.zones == [2] && right.target == layout.zones[1].frame)
    #expect(right.via == .keyboard && right.originalFrame == z[0] && right.display == F.displayA)
    #expect(try cycle(.cycleLeft, frame: z[0], record: rec1).0.zones == [4])

    // A Span record {1, 2}: Right continues after the highest, Left before the lowest.
    let union = z[0].union(z[1])
    let span: (WindowKey) -> LastSnapRecord = { LastSnapRecord(key: $0, display: F.displayA, zones: [1, 2], frame: union) }
    #expect(try cycle(.cycleRight, frame: union, record: span).0.zones == [3])
    #expect(try cycle(.cycleLeft, frame: union, record: span).0.zones == [4])

    // A clamped window (Calculator at Zone 3) still cycles to Zone 4.
    let clamped = CGRect(x: z[2].minX, y: z[2].minY, width: 300, height: 400)
    let calc: (WindowKey) -> LastSnapRecord = { LastSnapRecord(key: $0, display: F.displayA, zones: [3], frame: clamped) }
    #expect(try cycle(.cycleRight, frame: clamped, record: calc).0.zones == [4])

    // A hand move: the record no longer matches, so the Zone of maximum intersection is the base.
    let moved = z[2].insetBy(dx: 20, dy: 20)
    #expect(try cycle(.cycleRight, frame: moved, record: rec1).0.zones == [4])
    #expect(try cycle(.cycleLeft, frame: moved, record: rec1).0.zones == [2])
    // No record at all: same thing.
    #expect(try cycle(.cycleRight, frame: moved).0.zones == [4])

    checkRestore()
  }

  func checkRestore() {
    let sink = Self.installSink()
    defer { sink.reset() }
    let layouts = F.layouts(a: Self.columns4, b: Self.grid4)
    let win = F.focused(frame: CGRect(x: 0, y: 25, width: 480, height: 1055))
    let key = win.record.handle.key
    let original = CGRect(x: 300, y: 300, width: 700, height: 500)
    var registry = OriginalFrameRegistry()

    // No entry: noOp(noEntry) with one log line.
    let none = ShortcutResolver.plan(
      .restore, focused: win, verdict: .allow(.full), topology: F.topology, layouts: layouts, registry: registry)
    #expect(none == .noOp(.noEntry))
    #expect(sink.events.count == 1)

    // An entry: the plan is the entry and the RestorePlanner target; the registry is not touched.
    let entry = OriginalFrameEntry(key: key, frame: original, via: .keyboard)
    _ = registry.capture(entry)
    let before = registry
    sink.reset()
    let plan = ShortcutResolver.plan(
      .restore, focused: win, verdict: .allow(.full), topology: F.topology, layouts: layouts, registry: registry)
    #expect(plan == .restore(entry, target: original))
    #expect(sink.events.isEmpty)
    #expect(registry == before)
  }

  // MARK: through SnapService with FakeWindowSystem

  /// A Calculator-like window clamps the Zone 3 write; the read-back becomes the last-Snap record, and the next
  /// cycleRight targets Zone 4 (AC-100, AC-098).
  @Test @WindowActor func fakeSystemIntegration() throws {
    let clock = FakeClock()
    let ws = FakeWindowSystem(clock: clock)
    let handle = F.handle()
    let store = DocumentStore(fs: FakeFileSystem(), directory: URL(filePath: "/zones-test"), clock: clock)
    let service = SnapService(
      writer: FrameWriter(system: ws, recovery: EnhancedUIRecovery(store: store)), system: ws, clock: clock)
    var health = AppHealth()
    var registry = OriginalFrameRegistry()
    let layouts = F.layouts(a: Self.columns4, b: Self.grid4)
    let layoutA = try #require(layouts[F.displayA])

    // sendToZone(3) from a free-floating frame.
    let start = CGRect(x: 100, y: 200, width: 800, height: 600)
    let plan = ShortcutResolver.plan(
      .sendToZone(3), focused: F.focused(frame: start, handle: handle), verdict: .allow(.full), topology: F.topology,
      layouts: layouts, registry: registry)
    guard case .snap(let snap) = plan else {
      Issue.record("expected a snap plan, got \(plan)")
      return
    }
    #expect(snap.target == layoutA.zones[2].frame)
    // The caller captures the Original Frame from the plan, then executes it.
    _ = registry.capture(OriginalFrameEntry(key: handle.key, frame: try #require(snap.originalFrame), via: .keyboard))

    // The app refuses to grow past 300x400: pre-write read, read-back, follow-up read.
    let clamped = CGRect(x: snap.target.minX, y: snap.target.minY, width: 300, height: 400)
    ws.enqueue(.frame(.value(start)))
    ws.enqueue(.frame(.value(clamped)))
    ws.enqueue(.frame(.value(clamped)))
    let outcome = service.execute(snap, handle: handle, health: &health)
    #expect(outcome.result == .clamped(clamped))
    let readBack = try #require(outcome.readBack)
    registry.recordSnap(LastSnapRecord(key: handle.key, display: snap.display, zones: snap.zones, frame: readBack))

    // The window is still at the clamped frame: cycleRight goes to Zone 4, not back to Zone 3.
    let next = ShortcutResolver.plan(
      .cycleRight, focused: F.focused(frame: readBack, handle: handle), verdict: .allow(.full),
      topology: F.topology, layouts: layouts, registry: registry)
    guard case .snap(let nextSnap) = next else {
      Issue.record("expected a snap plan, got \(next)")
      return
    }
    #expect(nextSnap.zones == [4])
    #expect(nextSnap.target == layoutA.zones[3].frame)
    // The Original Frame is still the very first one.
    #expect(registry.entry(handle.key)?.frame == start)
  }
}
