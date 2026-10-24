import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesTestSupport

@testable import ZonesWindowing

@Suite struct InputSourceTests {
  static let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)

  // AC-065
  @Test func productionTapIsListenOnly() {
    #expect(TapConfig.production.listenOnly == true)
    #expect(TapConfig.production.mask == [.leftDown, .leftDragged, .leftUp, .flagsChanged])

    let source = EventTapInputSource(tapMaker: TapMaker { _, _ in nil }, primaryFrame: { Self.primary })
    #expect(source.config == .production)

    let expected: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
    let mask = EventTapInputSource.cgEventMask(for: .production)
    #expect(mask == expected.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) })
    let forbidden: [CGEventType] = [
      .rightMouseDown, .rightMouseDragged, .rightMouseUp, .otherMouseDown, .otherMouseDragged,
      .otherMouseUp, .keyDown, .keyUp, .mouseMoved, .scrollWheel,
    ]
    for type in forbidden {
      #expect(mask & (1 << CGEventMask(type.rawValue)) == 0, "\(type)")
    }
  }

  // AC-011
  @Test func reenableRateLimitThenTapLost() {
    var recovery = TapRecovery()
    #expect(recovery.state == .alive)
    for t in [0.0, 10, 20, 30, 59] {
      #expect(recovery.reduce(.disabledByTimeout, timer: nil, now: t) == [.reenable], "t=\(t)")
    }
    var sixth = recovery
    let lost = sixth.reduce(.disabledByTimeout, timer: nil, now: 59.5)
    #expect(lost == [.tapLost, .schedule(.deadTapRetry, Constants.deadTapRetry)])
    #expect(sixth.state == .dead)

    // The first entry ages out at 60 s, so the sixth call at 60.5 is still a re-enable.
    var aged = recovery
    #expect(aged.reduce(.disabledByTimeout, timer: nil, now: 60.5) == [.reenable])
    #expect(aged.state == .alive)
    #expect(aged.reenables == [10, 20, 30, 59, 60.5])

    // User-input disables count the same as timeouts.
    var mixed = TapRecovery()
    for t in [0.0, 1, 2, 3, 4] {
      #expect(mixed.reduce(.disabledByUserInput, timer: nil, now: t) == [.reenable])
    }
    #expect(mixed.reduce(.disabledByTimeout, timer: nil, now: 5) == lost)

    // Dead: the retry timer asks for a recreate; the result decides what happens next.
    #expect(sixth.reduce(nil, timer: .deadTapRetry, now: 89.5) == [.recreate])
    var failed = sixth
    #expect(failed.reduce(.recreated(false), timer: nil, now: 89.5) == [.schedule(.deadTapRetry, 30)])
    #expect(failed.state == .dead)
    var healed = sixth
    #expect(healed.reduce(.recreated(true), timer: nil, now: 89.5) == [.cancel(.deadTapRetry)])
    #expect(healed.state == .alive)
    #expect(healed.reenables.isEmpty)

    // Other timers and a stray disable while dead change nothing.
    var idle = sixth
    #expect(idle.reduce(nil, timer: .healthTick, now: 90) == [])
    #expect(idle.reduce(.disabledByTimeout, timer: nil, now: 90) == [])
    #expect(idle == sixth)
  }

  @Test func recoveryTimerIsPendingThenCancelled() {
    let clock = FakeClock()
    var recovery = TapRecovery()
    for t in [0.0, 1, 2, 3, 4] { _ = recovery.reduce(.disabledByTimeout, timer: nil, now: t) }
    var handles: [TimerID: TimerHandle] = [:]
    for effect in recovery.reduce(.disabledByTimeout, timer: nil, now: 5) {
      if case .schedule(let id, let after) = effect {
        handles[id] = clock.schedule(id, after: after, repeats: false) {}
      }
    }
    #expect(clock.pending == [.deadTapRetry])
    for effect in recovery.reduce(.recreated(true), timer: nil, now: 35) {
      if case .cancel(let id) = effect, let handle = handles[id] { clock.cancel(handle) }
    }
    #expect(clock.pending.isEmpty)
  }
}
