import CoreGraphics
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
@testable import ZonesWindowing

/// A live Span across a topology change mid-drag (T67, CHANGELOG 0.1.0 known issue from the T39 review). Rule (DG,
/// option A): the Span's numbers survive only while the Span's Display keeps the Layout they were swept on; a changed
/// Layout clears the set and the re-hit starts it again; a Display that is gone keeps the set suspended (US-063).
@Suite struct SpanTopologyTests {
  typealias F = DragFixtures

  static let held: ModifierSet = [.shift, .control]

  /// Display A of the drag fixture with a two-column Layout in place of the nine-Zone Grid.
  static func twoColumnContext() -> ArmContext {
    var twoColumns = Fixtures.nineZone
    twoColumns.id = LayoutID(rawValue: "test:two-columns")
    twoColumns.root = .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf)
    var ctx = F.context(displays: [0, 1])
    ctx.layouts[F.primaryKey] = LayoutMath.resolve(twoColumns, display: F.topology.displays[0])
    return ctx
  }

  /// Armed with both modifiers held on the nine-Zone Grid of Display A, swept over Zones 5 and 6.
  static func sweptFiveAndSix() -> DragState {
    let armContext = F.context(displays: [0, 1])
    let armed = DragSessionReducerTests.armedAt(F.center(5), context: armContext, flags: held)
    return DragSessionReducer.reduce(armed, .dragged(point: F.center(6), flags: held)).0
  }

  @Test func spanNumbersFromOldLayoutNeverReachTheDrop() throws {
    let swept = Self.sweptFiveAndSix()
    guard case .armed(_, _, _, _, _, _, _, let before, _, _) = swept else {
      Issue.record("not armed: \(swept)")
      return
    }
    #expect(before.zones == [5, 6])

    // The snapshot changes under the live Span: Display A now has two columns, so Zones 5 and 6 do not exist.
    let newCtx = Self.twoColumnContext()
    let (next, _) = DragSessionReducer.reduce(swept, .topologyChanged(newCtx))
    let numbers = Set(newCtx.layouts[F.primaryKey]!.zones.map(\.number))
    guard case .armed(_, _, _, _, _, _, _, let span, _, _) = next else {
      Issue.record("not armed after topologyChanged: \(next)")
      return
    }
    #expect(span.zones.isSubset(of: numbers), "stored Span \(span.zones) names Zones absent from \(numbers)")

    let (_, up) = DragSessionReducer.reduce(next, .mouseUp(point: F.center(6), flags: Self.held))
    guard case .snap(let plan)? = up.last else {
      Issue.record("no snap: \(up)")
      return
    }
    #expect(plan.zones.isSubset(of: numbers), "drop names Zones \(plan.zones) absent from \(numbers)")
    #expect(plan.target == Span.rect(plan.zones, in: newCtx.layouts[F.primaryKey]!))
  }

  @Test func spanRestartsAtRehitWhenLayoutChanges() throws {
    let newCtx = Self.twoColumnContext()
    let (next, fx) = DragSessionReducer.reduce(Self.sweptFiveAndSix(), .topologyChanged(newCtx))
    guard case .armed(_, _, _, _, _, _, let hit, let span, _, _) = next else {
      Issue.record("not armed after topologyChanged: \(next)")
      return
    }
    // The cursor (center of old Zone 6) is in the right column: the Span starts again there, and only there.
    #expect(hit == .zone(2))
    #expect(span == SpanState(zones: [2], display: F.primaryKey, frozen: false, suspended: false))
    #expect(fx.last == .updateHighlight(Highlight(display: F.primaryKey, primary: [2], secondary: [], dimAll: false)))
  }

  // MARK: SpanLogic.rebase

  static let a = F.primaryKey
  static let nine = F.context(displays: [0, 1])

  static func swept(_ zones: Set<Int>, frozen: Bool = false, suspended: Bool = false) -> SpanState {
    SpanState(zones: zones, display: a, frozen: frozen, suspended: suspended)
  }

  @Test func rebaseKeepsTheSetOnTheSameLayout() {
    // Display B leaves; A keeps its nine-Zone Layout, so the numbers still name the same Zones.
    let span = Self.swept([5, 6])
    #expect(SpanLogic.rebase(span, from: Self.nine, to: F.context(displays: [0])) == span)
    // A resolution change re-resolves the same Layout: same numbers, new rectangles.
    var resized = Self.nine
    var display = F.topology.displays[0]
    display.frame.size.width += 200
    display.visibleFrame.size.width += 200
    resized.layouts[Self.a] = LayoutMath.resolve(Fixtures.nineZone, display: display)
    #expect(SpanLogic.rebase(span, from: Self.nine, to: resized) == span)
  }

  @Test func rebaseClearsTheSetWhenTheLayoutChanges() {
    let cleared = SpanLogic.rebase(Self.swept([1, 2]), from: Self.nine, to: Self.twoColumnContext())
    // Both numbers exist in two columns but name other areas: cleared all the same.
    #expect(cleared == SpanState(zones: [], display: nil, frozen: false, suspended: false))
    // A frozen Span stays frozen: nothing joins until the Span Modifier is pressed again (US-062).
    let frozen = SpanLogic.rebase(Self.swept([5], frozen: true), from: Self.nine, to: Self.twoColumnContext())
    #expect(frozen == SpanState(zones: [], display: nil, frozen: true, suspended: false))
  }

  @Test func rebaseKeepsASuspendedSetWhileItsDisplayIsGone() {
    let span = Self.swept([5, 6], suspended: true)
    let gone = F.context(displays: [1, 2])
    #expect(SpanLogic.rebase(span, from: Self.nine, to: gone) == span)
    // The Display returns: its Assignment survives (AC-118), so the set is kept while every number exists ...
    #expect(SpanLogic.rebase(span, from: gone, to: Self.nine) == span)
    // ... and cleared when a number is missing from the Layout it returns with.
    #expect(SpanLogic.rebase(span, from: gone, to: Self.twoColumnContext()).zones.isEmpty)
  }

  @Test func rebaseLeavesAnEmptySpanAlone() {
    let empty = SpanState(zones: [], display: nil, frozen: true, suspended: false)
    #expect(SpanLogic.rebase(empty, from: Self.nine, to: Self.twoColumnContext()) == empty)
  }
}
