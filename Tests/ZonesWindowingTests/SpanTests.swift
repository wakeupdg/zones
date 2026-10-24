import CoreGraphics
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

/// Span accumulation and its drop set (AC-081, AC-083, AC-084, AC-086).
@Suite struct SpanTests {
  typealias F = DragFixtures

  static let shiftControl: ModifierSet = [.shift, .control]

  /// A 2 x 2 Grid with a Margin and a Gap: 1 top-left, 2 top-right, 3 bottom-left, 4 bottom-right.
  static let twoByTwo: Layout = {
    let column = SplitNode.split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf)
    return Layout(
      id: LayoutID(rawValue: "builtin:grid:4"), name: "Grid 4",
      root: .split(axis: .vertical, ratio: 0.5, first: column, second: column),
      surround: Surround(top: 0, left: 0, bottom: 0, right: 0), insets: Insets(margin: 8, gap: 8),
      builtIn: BuiltInRef(template: .grid, count: 4))
  }()

  static let twoByTwoContext = ArmContext(
    topology: F.topology, layouts: Fixtures.layouts(F.topology, twoByTwo),
    appearance: F.context.appearance, options: F.context.options, hasOriginalFrame: false)

  static let window = DragSessionReducerTests.windowCentered(in: 2)

  /// Armed through the harness with the Activation Modifier only, the cursor over Zone `n` of `context`.
  static func armed(over n: Int = 2, context: ArmContext = F.context) -> DragState {
    let at = F.center(n, context)
    return F.run(
      [
        F.mouseDown(flags: .shift, candidates: [window], point: F.center(2, context)), F.dragged(at),
        F.sample(window.frame.offsetBy(dx: 30, dy: 10)),
      ], context: context
    ).state
  }

  /// Feeds `events` to the reducer one after another; no `requestArmContext` replies.
  static func step(_ state: DragState, _ events: [DragEvent]) -> (state: DragState, effects: [DragEffect]) {
    var state = state
    var effects: [DragEffect] = []
    for event in events {
      let (next, out) = DragSessionReducer.reduce(state, event)
      state = next
      effects += out
    }
    return (state, effects)
  }

  static func drag(to p: CGPoint, flags: ModifierSet = shiftControl) -> DragEvent { .dragged(point: p, flags: flags) }

  static func span(_ s: DragState) -> SpanState {
    guard case .armed(_, _, _, _, _, _, _, let span) = s else {
      Issue.record("not armed: \(s)")
      return SpanState(zones: [], display: nil, frozen: false, suspended: false)
    }
    return span
  }

  static func lastHighlight(_ fx: [DragEffect]) -> Highlight? {
    for case .updateHighlight(let h) in fx.reversed() { return h }
    return nil
  }

  @Test func accumulateAndUnion() throws {
    // Sweep 1, 2, 3 in the nine-Zone Grid with the Span Modifier down.
    var run = Self.step(Self.armed(over: 2), [Self.drag(to: F.center(1), flags: .shift)])
    run = Self.step(run.state, [.flagsChanged(Self.shiftControl)])
    #expect(Self.span(run.state).zones == [1])
    for (zone, expected) in [(2, Set([1, 2])), (3, Set([1, 2, 3]))] {
      run = Self.step(run.state, [Self.drag(to: F.center(zone))])
      #expect(Self.span(run.state).zones == expected)
      #expect(Self.span(run.state).display == F.primaryKey)
      #expect(
        Self.lastHighlight(run.effects)
          == Highlight(display: F.primaryKey, primary: expected, secondary: [], dimAll: false))
    }
    // The bounding rectangle spans the Gaps between the Zones.
    let rowFrame = F.zoneFrame(1).union(F.zoneFrame(2)).union(F.zoneFrame(3))
    #expect(Span.rect([1, 2, 3], in: F.layout()) == rowFrame)

    // Re-sweeping 2 leaves the set unchanged, and no highlight change is emitted.
    run = Self.step(run.state, [Self.drag(to: F.center(2))])
    #expect(Self.span(run.state).zones == [1, 2, 3])
    run = Self.step(run.state, [Self.drag(to: F.center(3))])
    #expect(Self.span(run.state).zones == [1, 2, 3])

    // Dropping applies the whole set at once.
    let (idle, fx) = DragSessionReducer.reduce(run.state, .mouseUp(point: F.center(3), flags: Self.shiftControl))
    #expect(idle == .idle)
    guard case .snap(let plan)? = fx.last else {
      Issue.record("no snap in \(fx)")
      return
    }
    #expect(plan.zones == [1, 2, 3])
    #expect(plan.target == rowFrame)
    #expect(plan.display == F.primaryKey)

    // In a 2 x 2, Zones 1 and 4 span the whole Layout rectangle.
    let ctx = Self.twoByTwoContext
    var diag = Self.step(
      Self.armed(over: 1, context: ctx),
      [.flagsChanged(Self.shiftControl), Self.drag(to: F.center(1, ctx)), Self.drag(to: F.center(4, ctx))])
    #expect(Self.span(diag.state).zones == [1, 4])
    let layout = F.layout(ctx)
    // "The whole Layout" is the union of all four Zone frames: the Margin stays outside every Zone.
    let whole = Span.rect([1, 2, 3, 4], in: layout)
    #expect(whole == layout.layoutRect.insetBy(dx: 8, dy: 8))
    #expect(Span.rect([1, 4], in: layout) == whole)
    #expect(
      Self.lastHighlight(diag.effects)
        == Highlight(display: F.primaryKey, primary: [1, 4], secondary: [], dimAll: false))
    diag = Self.step(diag.state, [.mouseUp(point: F.center(4, ctx), flags: Self.shiftControl)])
    guard case .snap(let diagPlan)? = diag.effects.last else {
      Issue.record("no snap")
      return
    }
    #expect(diagPlan.zones == [1, 4])
    #expect(diagPlan.target == whole)
  }
}
