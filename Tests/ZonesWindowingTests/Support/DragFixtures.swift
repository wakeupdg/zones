import CoreGraphics
import Foundation
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

/// Builders and a harness for the Drag Session reducer tests.
enum DragFixtures {
  static let config = ModifierConfig(activation: .shift, span: .control)

  static let topology = Fixtures.threeDisplays
  static let primaryKey: DisplayKey = topology.displays[0].key

  /// A 9-Zone layout on every Display of `threeDisplays`.
  static let context = ArmContext(
    topology: topology, layouts: Fixtures.layouts(topology, Fixtures.nineZone),
    appearance: Preferences.defaults.appearance,
    options: AccessibilityOptions(reduceTransparency: false, reduceMotion: false), hasOriginalFrame: false)

  /// The same nine-Zone context restricted to the Displays at `indices` of `threeDisplays` (the arm snapshot).
  static func context(displays indices: [Int]) -> ArmContext {
    let kept = indices.map { topology.displays[$0] }
    let snapshot = TopologySnapshot(displays: kept, separateSpaces: topology.separateSpaces, primaryFrame: topology.primaryFrame)
    var ctx = context
    ctx.topology = snapshot
    ctx.layouts = context.layouts.filter { pair in kept.contains { $0.key == pair.key } }
    return ctx
  }

  static func center(of display: Int) -> CGPoint {
    let f = topology.displays[display].frame
    return CGPoint(x: f.midX, y: f.midY)
  }

  static let downFrame = CGRect(x: 100, y: 100, width: 400, height: 300)
  static let downPoint = CGPoint(x: 300, y: 250)

  static func ref(_ id: UInt32, pid: pid_t = 100, frame: CGRect = downFrame) -> WindowRef {
    WindowRef(id: WindowID(rawValue: id), pid: pid, bundleID: "test.app\(id)", frame: frame, layer: 0)
  }

  static let window = ref(1)

  static func layout(_ context: ArmContext = DragFixtures.context) -> ResolvedLayout {
    context.layouts[primaryKey]!
  }

  static func zoneFrame(_ n: Int, _ context: ArmContext = DragFixtures.context) -> CGRect {
    layout(context).zones.first { $0.number == n }!.frame
  }

  static func center(_ n: Int, _ context: ArmContext = DragFixtures.context) -> CGPoint {
    let f = zoneFrame(n, context)
    return CGPoint(x: f.midX, y: f.midY)
  }

  static func mouseDown(
    flags: ModifierSet = [], candidates: [WindowRef] = [window], phaseOne: Verdict = .allow(.full),
    point: CGPoint = downPoint, config: ModifierConfig = DragFixtures.config
  ) -> DragEvent {
    .mouseDown(point: point, flags: flags, candidates: candidates, phaseOne: phaseOne, config: config)
  }

  static func dragged(_ p: CGPoint = CGPoint(x: 320, y: 260)) -> DragEvent { .dragged(point: p, flags: []) }

  /// Phase-two facts of an ordinary, movable, standard window.
  static let standardFacts = WindowFacts(subrole: .standard, isFullScreen: false, positionSettable: true, sizeSettable: true)

  static func sample(_ frame: CGRect, id: UInt32 = 1, facts: WindowFacts? = standardFacts) -> DragEvent {
    .frameSample([WindowID(rawValue: id): .frame(frame, facts)])
  }

  static func unmoved(id: UInt32 = 1) -> DragEvent { sample(downFrame, id: id) }
  static func moved(id: UInt32 = 1) -> DragEvent { sample(downFrame.offsetBy(dx: 30, dy: 10), id: id) }

  /// Runs `events` through the reducer. Every `requestArmContext` is answered at once with
  /// `.armContext(context)`, followed by a replay of the last `dragged` point (the driver's job in the app).
  static func run(
    _ events: [DragEvent], from start: DragState = .idle, context: ArmContext = DragFixtures.context
  ) -> (state: DragState, effects: [DragEffect]) {
    var state = start
    var effects: [DragEffect] = []
    var lastDragged: DragEvent?
    var queue = events[...]
    while let event = queue.popFirst() {
      if case .dragged = event { lastDragged = event }
      let (next, out) = DragSessionReducer.reduce(state, event)
      state = next
      effects += out
      if out.contains(where: { if case .requestArmContext = $0 { true } else { false } }) {
        var replies: [DragEvent] = [.armContext(context)]
        if let lastDragged { replies.append(lastDragged) }
        queue = replies[...] + queue
      }
    }
    return (state, effects)
  }

  static func isShowOverlay(_ e: DragEffect) -> Bool { if case .showOverlay = e { true } else { false } }
  static func isRequestSample(_ e: DragEffect) -> Bool { if case .requestSample = e { true } else { false } }
  static func isRequestArmContext(_ e: DragEffect) -> Bool {
    if case .requestArmContext = e { true } else { false }
  }
  static func isSnap(_ e: DragEffect) -> Bool { if case .snap = e { true } else { false } }
  static func isRestore(_ e: DragEffect) -> Bool { if case .restore = e { true } else { false } }
  static func isHideOverlay(_ e: DragEffect) -> Bool { if case .hideOverlay = e { true } else { false } }

  static func isArmed(_ s: DragState) -> Bool { if case .armed = s { true } else { false } }
  static func isMoving(_ s: DragState) -> Bool { if case .moving = s { true } else { false } }
  static func isPressed(_ s: DragState) -> Bool { if case .pressed = s { true } else { false } }
}
