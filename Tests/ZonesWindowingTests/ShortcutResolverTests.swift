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
}
