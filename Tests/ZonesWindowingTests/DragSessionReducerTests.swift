import CoreGraphics
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

@Suite struct DragSessionReducerTests {
  typealias F = DragFixtures

  @Test func clickRequestsNoSample() {
    let down = DragSessionReducer.reduce(.idle, F.mouseDown())
    #expect(F.isPressed(down.0))
    #expect(down.1.isEmpty)

    let up = DragSessionReducer.reduce(down.0, .mouseUp(point: F.downPoint, flags: []))
    #expect(up.0 == .idle)
    #expect(up.1.isEmpty)

    let whole = F.run([F.mouseDown(), .mouseUp(point: F.downPoint, flags: [])])
    #expect(whole.state == .idle)
    #expect(whole.effects.isEmpty)
  }

  @Test func phaseOneSkipEmitsSkipAndStaysIdle() {
    let (s, fx) = DragSessionReducer.reduce(.idle, F.mouseDown(phaseOne: .skip(.ownProcess)))
    #expect(s == .idle)
    #expect(fx == [.skip(.ownProcess, F.window)])
  }

  @Test func emptyCandidatesStayIdle() {
    let (s, fx) = DragSessionReducer.reduce(.idle, F.mouseDown(candidates: []))
    #expect(s == .idle)
    #expect(fx.isEmpty)
  }

  @Test func ignoresSecondMouseDownCore() {
    let (pressed, _) = DragSessionReducer.reduce(.idle, F.mouseDown())
    let (s, fx) = DragSessionReducer.reduce(
      pressed, F.mouseDown(candidates: [F.ref(2, pid: 200)], point: CGPoint(x: 5, y: 5)))
    #expect(s == pressed)
    #expect(fx.isEmpty)
  }

  @Test func overlayOnlyAfterMovedSample() {
    let id = F.window.id
    var (state, fx) = DragSessionReducer.reduce(.idle, F.mouseDown(flags: .shift))
    #expect(fx.isEmpty)

    (state, fx) = DragSessionReducer.reduce(state, F.dragged())
    #expect(fx == [.requestSample([id])])

    (state, fx) = DragSessionReducer.reduce(state, F.unmoved())
    #expect(F.isPressed(state))
    #expect(!fx.contains(where: F.isShowOverlay))

    (state, fx) = DragSessionReducer.reduce(state, F.moved())
    #expect(F.isMoving(state))
    #expect(fx == [.stopSampling, .requestArmContext(window: F.window, point: F.downPoint)])
    #expect(!fx.contains(where: F.isShowOverlay))

    (state, fx) = DragSessionReducer.reduce(state, .armContext(F.context))
    #expect(F.isArmed(state))
    #expect(fx.filter(F.isShowOverlay).count == 1)
  }

  @Test func modifierFirstArmsAfterMove() throws {
    let r = F.run([.flagsChanged(.shift), F.mouseDown(flags: .shift), F.dragged(), F.moved()])
    #expect(F.isArmed(r.state))
    let overlays = r.effects.compactMap { fx -> OverlayScene? in
      if case .showOverlay(let scene) = fx { scene } else { nil }
    }
    #expect(overlays.count == 1)
    let scene = try #require(overlays.first)
    #expect(scene.layouts.count == Fixtures.threeDisplays.displays.count)
    #expect(Set(scene.layouts.map(\.display)) == Set(Fixtures.threeDisplays.displays.map(\.key)))
  }

  @Test func pauseThenMoveStillArms() {
    var (state, _) = DragSessionReducer.reduce(.idle, F.mouseDown(flags: .shift))
    (state, _) = DragSessionReducer.reduce(state, F.dragged())
    for _ in 0..<3 {
      let (next, fx) = DragSessionReducer.reduce(state, F.unmoved())
      #expect(F.isPressed(next))
      #expect(fx == [.requestSample([F.window.id])])
      state = next
    }
    // A timed-out or gone read counts as unmoved too.
    let (afterTimeout, fx) = DragSessionReducer.reduce(state, .frameSample([F.window.id: .timedOut]))
    #expect(F.isPressed(afterTimeout))
    #expect(fx == [.requestSample([F.window.id])])

    let (moving, _) = DragSessionReducer.reduce(afterTimeout, F.moved())
    #expect(F.isMoving(moving))

    let whole = F.run([
      F.mouseDown(flags: .shift), F.dragged(), F.unmoved(), F.unmoved(), F.unmoved(), F.moved(),
    ])
    #expect(F.isArmed(whole.state))
  }

  @Test func resizeFromEveryEdgeEndsSession() {
    let f = F.downFrame
    let d = 40.0
    let frames: [(String, CGRect)] = [
      ("left", CGRect(x: f.minX - d, y: f.minY, width: f.width + d, height: f.height)),
      ("right", CGRect(x: f.minX, y: f.minY, width: f.width + d, height: f.height)),
      ("top", CGRect(x: f.minX, y: f.minY, width: f.width, height: f.height + d)),
      ("bottom", CGRect(x: f.minX, y: f.minY - d, width: f.width, height: f.height + d)),
      ("top-left", CGRect(x: f.minX - d, y: f.minY, width: f.width + d, height: f.height + d)),
      ("top-right", CGRect(x: f.minX, y: f.minY, width: f.width + d, height: f.height + d)),
      ("bottom-left", CGRect(x: f.minX - d, y: f.minY - d, width: f.width + d, height: f.height + d)),
      ("bottom-right", CGRect(x: f.minX, y: f.minY - d, width: f.width + d, height: f.height + d)),
    ]
    for (name, frame) in frames {
      var (state, _) = DragSessionReducer.reduce(.idle, F.mouseDown(flags: .shift))
      (state, _) = DragSessionReducer.reduce(state, F.dragged())
      let (next, fx) = DragSessionReducer.reduce(state, F.sample(frame))
      #expect(next == .idle, "\(name)")
      #expect(!fx.contains(where: F.isShowOverlay), "\(name)")
      #expect(!fx.contains(where: F.isRequestArmContext), "\(name)")
      #expect(fx == [.stopSampling], "\(name)")
    }
  }

  @Test func resizeToleranceIsOnePoint() {
    func outcome(_ dw: Double) -> DragState {
      var (state, _) = DragSessionReducer.reduce(.idle, F.mouseDown(flags: .shift))
      (state, _) = DragSessionReducer.reduce(state, F.dragged())
      let f = F.downFrame
      return DragSessionReducer.reduce(
        state, F.sample(CGRect(x: f.minX, y: f.minY, width: f.width + dw, height: f.height))
      ).0
    }
    #expect(F.isPressed(outcome(1.0)))
    #expect(outcome(1.01) == .idle)
  }

  @Test func modifierLateArms() {
    var (state, fx) = DragSessionReducer.reduce(.idle, F.mouseDown())
    (state, fx) = DragSessionReducer.reduce(state, F.dragged())
    (state, fx) = DragSessionReducer.reduce(state, F.moved())
    #expect(F.isMoving(state))
    #expect(fx == [.stopSampling])
    #expect(!fx.contains(where: F.isShowOverlay))

    (state, fx) = DragSessionReducer.reduce(state, .flagsChanged(.shift))
    #expect(F.isMoving(state))
    #expect(fx == [.requestArmContext(window: F.window, point: F.downFrame.origin)])

    // Shift already present: a repeated flagsChanged does not ask again.
    let (again, againFx) = DragSessionReducer.reduce(state, .flagsChanged([.shift, .option]))
    #expect(again != .idle)
    #expect(againFx.isEmpty)

    (state, fx) = DragSessionReducer.reduce(state, .armContext(F.context))
    #expect(F.isArmed(state))
    #expect(fx.filter(F.isShowOverlay).count == 1)

    let whole = F.run([F.mouseDown(), F.dragged(), F.moved(), .flagsChanged(.shift)])
    #expect(F.isArmed(whole.state))
    #expect(whole.effects.filter(F.isShowOverlay).count == 1)
  }

  @Test func plainDragIsInert() {
    let r = F.run([F.mouseDown(), F.dragged(), F.moved(), F.dragged(CGPoint(x: 400, y: 300))])
    #expect(F.isMoving(r.state))
    let (state, fx) = DragSessionReducer.reduce(r.state, .mouseUp(point: CGPoint(x: 400, y: 300), flags: []))
    #expect(state == .idle)
    #expect(fx.isEmpty)
    #expect(!r.effects.contains(where: F.isShowOverlay))
    #expect(!r.effects.contains(where: F.isSnap))
    #expect(!r.effects.contains(where: F.isRestore))
  }

  /// A window whose center sits in Zone `n`.
  static func windowCentered(in n: Int, id: UInt32 = 1, pid: pid_t = 100) -> WindowRef {
    let c = F.center(n)
    return F.ref(id, pid: pid, frame: CGRect(x: c.x - 100, y: c.y - 75, width: 200, height: 150))
  }

  /// Armed state reached through the harness; the window starts centered in Zone 2.
  static func armedOverZone2() -> (state: DragState, effects: [DragEffect]) {
    let w = windowCentered(in: 2)
    return F.run([
      F.mouseDown(flags: .shift, candidates: [w], point: F.center(2)), F.dragged(F.center(2)),
      F.sample(w.frame.offsetBy(dx: 30, dy: 10)),
    ])
  }

  @Test func highlightFollowsCursorNotWindow() {
    let (armed, armFx) = Self.armedOverZone2()
    #expect(F.isArmed(armed))
    // The replayed dragged sets the first highlight (CONTRACT-NOTE: hit is .none until then).
    #expect(
      armFx.last == .updateHighlight(
        Highlight(display: F.primaryKey, primary: [2], secondary: [], dimAll: false)))

    let (next, fx) = DragSessionReducer.reduce(armed, .dragged(point: F.center(3), flags: []))
    #expect(fx == [.updateHighlight(Highlight(display: F.primaryKey, primary: [3], secondary: [], dimAll: false))])
    guard case .armed(_, _, _, _, _, let display, let hit, _) = next else {
      Issue.record("not armed")
      return
    }
    #expect(display == F.primaryKey)
    #expect(hit == .zone(3))

    let (same, none) = DragSessionReducer.reduce(next, .dragged(point: F.center(3), flags: []))
    #expect(same == next)
    #expect(none.isEmpty)

    // Off every Display: no Zone, empty highlight.
    let (off, offFx) = DragSessionReducer.reduce(next, .dragged(point: CGPoint(x: 9000, y: 9000), flags: []))
    #expect(offFx == [.updateHighlight(Highlight(display: nil, primary: [], secondary: [], dimAll: false))])
    #expect(F.isArmed(off))
  }

  @Test func highlightUsesTheLayoutOfTheDisplayUnderTheCursor() {
    let (armed, _) = Self.armedOverZone2()
    let left = F.topology.displays[1]
    let layout = F.context.layouts[left.key]!
    let zone = layout.zones.first { $0.number == 5 }!.frame
    let p = CGPoint(x: zone.midX, y: zone.midY)
    let (_, fx) = DragSessionReducer.reduce(armed, .dragged(point: p, flags: []))
    #expect(fx == [.updateHighlight(Highlight(display: left.key, primary: [5], secondary: [], dimAll: false))])
  }

  @Test func modifierReleaseCancels() {
    let (armed, _) = Self.armedOverZone2()
    let (state, fx) = DragSessionReducer.reduce(armed, .flagsChanged([]))
    #expect(F.isMoving(state))
    #expect(fx == [.hideOverlay])
    guard case .moving(_, _, let flags, _) = state else { return }
    #expect(flags.isEmpty)

    let (idle, upFx) = DragSessionReducer.reduce(state, .mouseUp(point: F.center(3), flags: []))
    #expect(idle == .idle)
    #expect(!upFx.contains(where: F.isSnap))
    #expect(!upFx.contains(where: F.isRestore))

    // Another modifier is not the Activation Modifier: still a cancel.
    let (other, otherFx) = DragSessionReducer.reduce(armed, .flagsChanged(.option))
    #expect(F.isMoving(other))
    #expect(otherFx == [.hideOverlay])

    // Shift still held: nothing changes.
    let (kept, keptFx) = DragSessionReducer.reduce(armed, .flagsChanged([.shift, .option]))
    #expect(F.isArmed(kept))
    #expect(keptFx.isEmpty)

    // Pressing Shift again after the cancel re-arms (a new overlay).
    let whole = F.run([.flagsChanged([]), .flagsChanged(.shift)], from: armed)
    #expect(F.isArmed(whole.state))
    #expect(whole.effects.filter(F.isHideOverlay).count == 1)
    #expect(whole.effects.filter(F.isShowOverlay).count == 1)
  }

  @Test func snapOnlyWithModifierAtMouseUp() throws {
    let (armed, _) = Self.armedOverZone2()
    let w = Self.windowCentered(in: 2)

    let (idle, fx) = DragSessionReducer.reduce(armed, .mouseUp(point: F.center(3), flags: .shift))
    #expect(idle == .idle)
    #expect(fx.count == 2)
    guard case .snap(let plan)? = fx.last else {
      Issue.record("no snap in \(fx)")
      return
    }
    #expect(plan.zones == [3])
    #expect(plan.target == F.zoneFrame(3))
    #expect(plan.display == F.primaryKey)
    #expect(plan.window == w)
    #expect(plan.mode == .full)
    #expect(plan.via == .mouse)
    #expect(plan.originalFrame == w.frame)

    // Stored flags are not consulted: the mouse-up flags decide.
    let (_, noMod) = DragSessionReducer.reduce(armed, .mouseUp(point: F.center(3), flags: []))
    #expect(noMod == [.hideOverlay])
    let (_, wrongMod) = DragSessionReducer.reduce(armed, .mouseUp(point: F.center(3), flags: .option))
    #expect(wrongMod == [.hideOverlay])

    // The hit is recomputed from the mouse-up point, not the last highlight.
    let (_, fresh) = DragSessionReducer.reduce(armed, .mouseUp(point: F.center(7), flags: .shift))
    guard case .snap(let freshPlan)? = fresh.last else {
      Issue.record("no snap in \(fresh)")
      return
    }
    #expect(freshPlan.zones == [7])

    // A drop in the Gap between Zones goes to the nearest Zone (lower number on a tie).
    let z1 = F.zoneFrame(1)
    let gap = CGPoint(x: z1.maxX + 4, y: z1.midY)
    let (_, gapFx) = DragSessionReducer.reduce(armed, .mouseUp(point: gap, flags: .shift))
    guard case .snap(let gapPlan)? = gapFx.last else {
      Issue.record("no snap in \(gapFx)")
      return
    }
    #expect(gapPlan.zones == [1])

    // Off every Display: nothing to snap to.
    let (_, off) = DragSessionReducer.reduce(armed, .mouseUp(point: CGPoint(x: 9000, y: 9000), flags: .shift))
    #expect(off == [.hideOverlay])
  }

  @Test func snapOmitsOriginalFrameWhenOneIsRecorded() {
    var context = F.context
    context.hasOriginalFrame = true
    let w = Self.windowCentered(in: 2)
    let r = F.run(
      [
        F.mouseDown(flags: .shift, candidates: [w], point: F.center(2)), F.dragged(F.center(2)),
        F.sample(w.frame.offsetBy(dx: 30, dy: 10)), .mouseUp(point: F.center(4), flags: .shift),
      ], context: context)
    #expect(r.state == .idle)
    guard case .snap(let plan)? = r.effects.last else {
      Issue.record("no snap")
      return
    }
    #expect(plan.originalFrame == nil)
    #expect(plan.zones == [4])
  }

  @Test func hideOverlayPrecedesSnap() throws {
    let (armed, _) = Self.armedOverZone2()
    let (_, snapStep) = DragSessionReducer.reduce(armed, .mouseUp(point: F.center(3), flags: .shift))
    let hide = try #require(snapStep.firstIndex(where: F.isHideOverlay))
    let snap = try #require(snapStep.firstIndex(where: F.isSnap))
    #expect(hide < snap)

    let (_, plainStep) = DragSessionReducer.reduce(armed, .mouseUp(point: F.center(3), flags: []))
    #expect(plainStep.first == .hideOverlay)
    #expect(!plainStep.contains(where: F.isSnap))
    #expect(!plainStep.contains(where: F.isRestore))
  }
}
