import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

/// Original Frame registry: a pure value type, so every test drives it directly (ADR-0009 amended).
@Suite struct OriginalFrameRegistryTests {
  static let w1 = WindowKey(pid: 100, elementHash: 1)
  static let w2 = WindowKey(pid: 100, elementHash: 2)
  static let frameA = CGRect(x: 10, y: 20, width: 600, height: 400)
  static let frameB = CGRect(x: 300, y: 300, width: 500, height: 300)
  static let display = DisplayKey.uuid("11111111-1111-4111-8111-111111111111")

  /// AC-089: first capture wins on both paths; a later Snap never overwrites.
  @Test func firstSnapCapturesPerPath() {
    var registry = OriginalFrameRegistry()

    // Mouse path: the mouse-down frame of the resolved window.
    let mouse = OriginalFrameEntry(key: Self.w1, frame: Self.frameA, via: .mouse)
    let first = registry.capture(mouse)
    #expect(first)
    #expect(registry.entry(Self.w1) == mouse)

    // A second applied Snap offers a different frame: refused, entry unchanged.
    let later = OriginalFrameEntry(key: Self.w1, frame: Self.frameB, via: .mouse)
    let second = registry.capture(later)
    #expect(!second)
    #expect(registry.entry(Self.w1) == mouse)
    let otherPath = registry.capture(
      OriginalFrameEntry(key: Self.w1, frame: Self.frameB, via: .keyboard))
    #expect(!otherPath)
    #expect(registry.entry(Self.w1)?.via == .mouse)

    // Keyboard path: the pre-write read-back frame, tagged keyboard.
    let keyboard = OriginalFrameEntry(key: Self.w2, frame: Self.frameB, via: .keyboard)
    let keyboardFirst = registry.capture(keyboard)
    #expect(keyboardFirst)
    #expect(registry.entry(Self.w2) == keyboard)
    #expect(registry.entry(Self.w2)?.via == .keyboard)
    let keyboardAgain = registry.capture(
      OriginalFrameEntry(key: Self.w2, frame: Self.frameA, via: .keyboard))
    #expect(!keyboardAgain)
    #expect(registry.entry(Self.w2)?.frame == Self.frameB)

    // recordSnap stores the last applied frame and leaves the entry alone.
    let record = LastSnapRecord(
      key: Self.w1, display: Self.display, zones: [1], frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    registry.recordSnap(record)
    #expect(registry.lastSnap(Self.w1) == record)
    #expect(registry.entry(Self.w1) == mouse)
    #expect(registry.lastSnap(Self.w2) == nil)

    // Unknown windows have nothing.
    #expect(registry.entry(WindowKey(pid: 5, elementHash: 5)) == nil)
  }

  static let otherPid = WindowKey(pid: 200, elementHash: 1)

  static func snapRecord(_ key: WindowKey) -> LastSnapRecord {
    LastSnapRecord(
      key: key, display: display, zones: [1], frame: CGRect(x: 0, y: 25, width: 960, height: 1055))
  }

  /// AC-093: what forgets an entry, what does not, and that nothing is scheduled.
  @Test @WindowActor func forgetRules() {
    var rig = RestoreTests.Rig()
    let key = rig.key

    // (a) Snap, Restore, hand-move, Snap, Restore returns the hand-placed frame.
    let handPlaced = CGRect(x: 500, y: 150, width: 640, height: 480)
    rig.capture(Self.frameA)
    rig.registry.recordSnap(Self.snapRecord(key))
    rig.ws.enqueue(.frame(.value(Self.frameA)))
    #expect(rig.restoreFocused() == .applied(Self.frameA))
    #expect(rig.registry.entry(key) == nil)
    #expect(rig.registry.lastSnap(key) == nil)
    // The user drags the window by hand; the next Snap captures where it is now.
    let recaptured = rig.registry.capture(OriginalFrameEntry(key: key, frame: handPlaced, via: .mouse))
    #expect(recaptured)
    rig.registry.recordSnap(Self.snapRecord(key))
    rig.ws.enqueue(.frame(.value(handPlaced)))
    #expect(rig.restoreFocused() == .applied(handPlaced))
    #expect(rig.registry.entry(key) == nil)

    // (b) destroyed forgets that window only.
    var registry = OriginalFrameRegistry()
    for k in [Self.w1, Self.w2, Self.otherPid] {
      _ = registry.capture(OriginalFrameEntry(key: k, frame: Self.frameA, via: .mouse))
      registry.recordSnap(Self.snapRecord(k))
    }
    registry.apply(.destroyed(Self.w1))
    #expect(registry.entry(Self.w1) == nil)
    #expect(registry.lastSnap(Self.w1) == nil)
    #expect(registry.entry(Self.w2) != nil)
    #expect(registry.lastSnap(Self.w2) != nil)
    #expect(registry.entry(Self.otherPid) != nil)

    // (d) moved and apiDisabled are bookkeeping: nothing changes.
    let before = registry
    registry.apply(.moved(Self.w2))
    registry.apply(.apiDisabled)
    #expect(registry == before)

    // (c) appTerminated evicts every entry and last Snap of that pid, and none of another pid.
    registry.apply(.appTerminated(Self.w2.pid))
    #expect(registry.entry(Self.w2) == nil)
    #expect(registry.lastSnap(Self.w2) == nil)
    #expect(registry.entry(Self.otherPid) != nil)
    #expect(registry.lastSnap(Self.otherPid) != nil)
    registry.evict(pid: Self.otherPid.pid)
    #expect(registry == OriginalFrameRegistry())

    // (e) A write that finds the element gone forgets the key at that touch.
    var gone = RestoreTests.Rig()
    gone.capture(Self.frameA)
    gone.registry.recordSnap(Self.snapRecord(gone.key))
    gone.ws.enqueue(.size(.elementGone))
    #expect(gone.restoreFocused() == .failed(.elementGone))
    #expect(gone.registry.entry(gone.key) == nil)
    #expect(gone.registry.lastSnap(gone.key) == nil)

    // (f) No periodic sweep: no timer was scheduled by any of this.
    #expect(rig.clock.pending.isEmpty)
    #expect(gone.clock.pending.isEmpty)
  }
}
