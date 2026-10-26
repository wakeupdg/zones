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
    guard case .armed(_, _, _, _, _, _, _, let span, _, _) = s else {
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

  @Test func freezeResumeClear() {
    // Span {1, 2} on the nine-Zone Grid.
    var run = Self.step(
      Self.armed(over: 1),
      [.flagsChanged(Self.shiftControl), Self.drag(to: F.center(2))])
    #expect(Self.span(run.state).zones == [1, 2])
    #expect(!Self.span(run.state).frozen)

    // Releasing the Span Modifier freezes the set; sweeping on adds nothing and the highlight stays.
    run = Self.step(run.state, [.flagsChanged(.shift)])
    #expect(Self.span(run.state).frozen)
    #expect(Self.span(run.state).zones == [1, 2])
    #expect(run.effects.isEmpty)
    run = Self.step(run.state, [Self.drag(to: F.center(5), flags: .shift), Self.drag(to: F.center(6), flags: .shift)])
    #expect(Self.span(run.state).zones == [1, 2])
    #expect(run.effects.isEmpty)

    // A drop applies the frozen set, wherever the cursor is.
    let (_, dropFx) = DragSessionReducer.reduce(run.state, .mouseUp(point: F.center(6), flags: .shift))
    guard case .snap(let plan)? = dropFx.last else {
      Issue.record("no snap in \(dropFx)")
      return
    }
    #expect(plan.zones == [1, 2])

    // Pressing it again resumes adding, starting with the Zone under the cursor (6).
    run = Self.step(run.state, [.flagsChanged(Self.shiftControl)])
    #expect(!Self.span(run.state).frozen)
    #expect(Self.span(run.state).zones == [1, 2, 6])
    run = Self.step(run.state, [Self.drag(to: F.center(9))])
    #expect(Self.span(run.state).zones == [1, 2, 6, 9])

    // Releasing the Activation Modifier clears the Span: the session leaves armed and the overlay hides.
    let armedBefore = run.state
    run = Self.step(armedBefore, [.flagsChanged([.control])])
    #expect(F.isMoving(run.state))
    #expect(run.effects == [.hideOverlay])

    // Pressing it again re-arms with a fresh Span: only the single cursor Zone is lit.
    let w = Self.window
    let rearmed = F.run(
      [
        F.mouseDown(flags: Self.shiftControl, candidates: [w], point: F.center(2)),
        Self.drag(to: F.center(1)), F.sample(w.frame.offsetBy(dx: 30, dy: 10)),
        Self.drag(to: F.center(2)), Self.drag(to: F.center(3)), .flagsChanged([.control]),
        .flagsChanged(Self.shiftControl),
      ])
    #expect(F.isArmed(rearmed.state))
    #expect(Self.span(rearmed.state).zones == [3])
    #expect(
      Self.lastHighlight(rearmed.effects)
        == Highlight(display: F.primaryKey, primary: [3], secondary: [], dimAll: false))
  }

  @Test func bothModifiersBeforeMove() {
    let w = Self.window
    let moved = F.sample(w.frame.offsetBy(dx: 30, dy: 10))

    // Both modifiers down at mouse-down: the arming sample starts the Span with the Zone under the cursor.
    let over = F.run([
      F.mouseDown(flags: Self.shiftControl, candidates: [w], point: F.center(2)), Self.drag(to: F.center(2)), moved,
    ])
    #expect(F.isArmed(over.state))
    #expect(over.effects.contains(where: F.isShowOverlay))
    #expect(Self.span(over.state).zones == [2])
    #expect(Self.span(over.state).display == F.primaryKey)
    #expect(
      Self.lastHighlight(over.effects)
        == Highlight(display: F.primaryKey, primary: [2], secondary: [], dimAll: false))

    // Over a Gap the Span starts empty; the nearest Zone is lit as a single-Zone drop but is not a Zone entered.
    let z1 = F.zoneFrame(1)
    let gap = CGPoint(x: z1.maxX + 4, y: z1.midY)
    let gapRun = F.run([
      F.mouseDown(flags: Self.shiftControl, candidates: [w], point: gap), Self.drag(to: gap), moved,
    ])
    #expect(F.isArmed(gapRun.state))
    #expect(Self.span(gapRun.state).zones.isEmpty)
    #expect(Self.span(gapRun.state).display == nil)
    #expect(
      Self.lastHighlight(gapRun.effects)
        == Highlight(display: F.primaryKey, primary: [1], secondary: [], dimAll: false))

    // Entering the first Zone adds it and sets the Span's Display.
    let entered = Self.step(gapRun.state, [Self.drag(to: F.center(5))])
    #expect(Self.span(entered.state).zones == [5])
    #expect(Self.span(entered.state).display == F.primaryKey)
    #expect(
      Self.lastHighlight(entered.effects)
        == Highlight(display: F.primaryKey, primary: [5], secondary: [], dimAll: false))

    // The Span Modifier pressed between mouse-down and the move counts too (still before the arming sample).
    let late = F.run([
      F.mouseDown(flags: .shift, candidates: [w], point: F.center(2)), Self.drag(to: F.center(2), flags: .shift),
      .flagsChanged(Self.shiftControl), moved,
    ])
    #expect(Self.span(late.state).zones == [2])
  }

  /// The center of Zone `n` on the Display at `index` of the fixture topology.
  static func center(_ n: Int, onDisplay index: Int) -> CGPoint {
    let key = F.topology.displays[index].key
    let f = F.context.layouts[key]!.zones.first { $0.number == n }!.frame
    return CGPoint(x: f.midX, y: f.midY)
  }

  @Test func suspendAndResumeAcrossDisplays() {
    let b = F.topology.displays[1].key
    // Span {1, 2, 3} on Display A (the primary Display).
    var run = Self.step(
      Self.armed(over: 1),
      [.flagsChanged(Self.shiftControl), Self.drag(to: F.center(2)), Self.drag(to: F.center(3))])
    #expect(Self.span(run.state).zones == [1, 2, 3])
    #expect(!Self.span(run.state).suspended)
    let onA = Self.span(run.state)

    // Crossing to Display B, over its Zone 2: the Span is suspended, kept as it was, and drawn secondary.
    run = Self.step(run.state, [Self.drag(to: Self.center(2, onDisplay: 1))])
    var span = Self.span(run.state)
    #expect(span.suspended)
    #expect(span.zones == [1, 2, 3])
    #expect(span.display == F.primaryKey)
    #expect(
      Self.lastHighlight(run.effects) == Highlight(
          display: b, primary: [2], secondary: [1, 2, 3], secondaryDisplay: F.primaryKey, dimAll: false))

    // Sweeping on B with the Span Modifier down adds nothing; releasing and pressing it changes only the flag.
    run = Self.step(run.state, [Self.drag(to: Self.center(5, onDisplay: 1))])
    #expect(Self.span(run.state).zones == [1, 2, 3])
    #expect(
      Self.lastHighlight(run.effects) == Highlight(
          display: b, primary: [5], secondary: [1, 2, 3], secondaryDisplay: F.primaryKey, dimAll: false))
    run = Self.step(run.state, [.flagsChanged(.shift), .flagsChanged(Self.shiftControl)])
    span = Self.span(run.state)
    #expect(span.zones == [1, 2, 3])
    #expect(span.suspended)
    run = Self.step(run.state, [Self.drag(to: Self.center(2, onDisplay: 1))])

    // Back on A: resumed, and the highlight is the Span again.
    let back = Self.step(run.state, [Self.drag(to: F.center(3))])
    span = Self.span(back.state)
    #expect(!span.suspended)
    #expect(span.zones == onA.zones)
    #expect(
      Self.lastHighlight(back.effects)
        == Highlight(display: F.primaryKey, primary: [1, 2, 3], secondary: [], dimAll: false))
    // Returning over a new Zone resumes adding.
    let more = Self.step(back.state, [Self.drag(to: F.center(6))])
    #expect(Self.span(more.state).zones == [1, 2, 3, 6])

    // Dropping on B while suspended snaps to B's cursor Zone only.
    let (idle, fx) = DragSessionReducer.reduce(
      run.state, .mouseUp(point: Self.center(2, onDisplay: 1), flags: Self.shiftControl))
    #expect(idle == .idle)
    guard case .snap(let plan)? = fx.last else {
      Issue.record("no snap in \(fx)")
      return
    }
    #expect(plan.display == b)
    #expect(plan.zones == [2])
    #expect(plan.target == F.context.layouts[b]!.zones.first { $0.number == 2 }!.frame)
    #expect(F.isHideOverlay(fx[0]))
  }
}
