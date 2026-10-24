import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesWindowing

private let window = WindowRef(
  id: WindowID(rawValue: 7), pid: 100, bundleID: "com.example.app",
  frame: CGRect(x: 10, y: 20, width: 300, height: 200), layer: 0)
private let config = ModifierConfig(activation: .shift, span: .control)
private let display = DisplayKey.uuid("11111111-1111-4111-8111-111111111111")
private let scene = OverlayScene(
  layouts: [], appearance: Preferences.defaults.appearance,
  options: AccessibilityOptions(reduceTransparency: false, reduceMotion: true))
private let context = ArmContext(
  topology: TopologySnapshot(displays: [], separateSpaces: true, primaryFrame: .zero),
  layouts: [:], appearance: Preferences.defaults.appearance,
  options: AccessibilityOptions(reduceTransparency: false, reduceMotion: false),
  hasOriginalFrame: false)

@Test func dragStateIdleAndPressedAreHashable() {
  let pressed = DragState.pressed(
    candidates: [window], down: CGPoint(x: 5, y: 5), downFrames: [window.id: window.frame],
    flags: [.shift], config: config, samples: 0, retried: false)
  let moving = DragState.moving(window: window, downFrame: window.frame, flags: [.shift], config: config)
  let armed = DragState.armed(
    window: window, downFrame: window.frame, flags: [.shift], config: config, context: context,
    display: display, hit: .zone(2),
    span: SpanState(zones: [2], display: display, frozen: false, suspended: false))
  #expect(Set([DragState.idle, pressed, moving, armed]).count == 4)
  #expect(pressed == pressed)
  #expect(DragState.idle != pressed)
}

@Test func dragEffectAndEventConstruct() {
  let plan = SnapPlan(
    window: window, display: display, zones: [1], target: window.frame, mode: .full, via: .mouse,
    originalFrame: nil)
  let highlight = Highlight(display: display, primary: [1], secondary: [], dimAll: false)
  let events: [DragEvent] = [
    .mouseDown(
      point: .zero, flags: [], candidates: [window], phaseOne: .allow(.full), config: config),
    .dragged(point: .zero, flags: [.shift]), .mouseUp(point: .zero, flags: []),
    .flagsChanged([.control]), .frameSample([window.id: .frame(window.frame, nil)]),
    .armContext(context), .windowGone, .topologyChanged(context), .spaceChanged, .wake,
  ]
  let effects: [DragEffect] = [
    .requestSample([window.id]), .stopSampling, .requestArmContext(window: window, point: .zero),
    .showOverlay(scene), .updateHighlight(highlight), .hideOverlay, .reassertPanels, .snap(plan),
    .restore(window, downFrame: window.frame), .skip(.ownProcess, nil), .log("x"),
  ]
  #expect(Set(events).count == 10)
  #expect(Set(effects).count == 11)
  #expect(SampleResult.timedOut != SampleResult.gone)
}

@Test func permissionStateEquality() {
  #expect(PermissionState.suspect(since: 1) == .suspect(since: 1))
  #expect(PermissionState.suspect(since: 1) != .suspect(since: 2))
  #expect(PermissionState.revoked(failures: 2, firstFailure: nil) != .revoked(failures: 2, firstFailure: 3))
  let events: [PermissionEvent] = [
    .probe(true), .apiDisabled, .tapNil, .tapRecreated(false), .trivialRead(.ok), .heartbeat(.timedOut),
    .timer(.trustPoll), .wake, .reonboard, .quit,
  ]
  #expect(Set(events).count == 10)
  #expect(PermissionEffect.schedule(.healthTick, 2) != .cancel(.healthTick))
  #expect(PermissionConfig(launchedAtLogin: true, heartbeatEnabled: false, reducerIdle: true).reducerIdle)
  #expect(Set([TapState.alive, .dead, .unavailable]).count == 3)
}

@Test func lifecycleEffectHasEightCases() {
  let all: Set<LifecycleEffect> = [
    .disableTap, .invalidateTap, .orderPanelsOut, .drainEnhancedUI, .removeRecoveryRecord, .revalidateTap,
    .probe, .forceTopologySnapshot,
  ]
  #expect(all.count == 8)
}

@Test func snapPlanAndAppHealthConstruct() {
  let plan = SnapPlan(
    window: window, display: display, zones: [1, 2], target: window.frame, mode: .positionOnly,
    via: .keyboard, originalFrame: CGRect(x: 0, y: 0, width: 10, height: 10))
  #expect(plan.zones == [1, 2])
  #expect(plan.via == .keyboard)
  let health = AppHealth(unresponsiveSince: [100: 5])
  #expect(health == AppHealth(unresponsiveSince: [100: 5]))
  #expect(AppHealth() == AppHealth(unresponsiveSince: [:]))
  let record = RecoveryRecord(
    bundleID: "com.example.app", pid: 100, launchDate: Date(timeIntervalSince1970: 0),
    priorEnhancedUI: true)
  #expect(record.priorEnhancedUI)
}
