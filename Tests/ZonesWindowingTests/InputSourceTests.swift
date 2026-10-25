import CoreGraphics
import Foundation
import Testing
import os
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

  // AC-011
  @Test func nilTapReportsUnavailable() async {
    let source = EventTapInputSource(tapMaker: TapMaker { _, _ in nil }, primaryFrame: { Self.primary })
    #expect(source.start() == .unavailable)
    #expect(source.reenable() == false)
    #expect(source.recreate() == .unavailable)
    var signals = source.signals.makeAsyncIterator()
    #expect(await signals.next() == .recreated(false))
    source.stop()

    var recovery = TapRecovery()
    #expect(recovery.reduce(.recreated(false), timer: nil, now: 0) == [.tapUnavailable])
    #expect(recovery.state == .unavailable)
  }

  /// A plain Mach port stands in for the tap, so the thread, run loop source and teardown run for real.
  @Test func lifecycleStartsStopsAndRecreates() async {
    let made = OSAllocatedUnfairLock(initialState: 0)
    let maker = TapMaker { _, _ in
      made.withLock { $0 += 1 }
      return CFMachPortCreate(nil, nil, nil, nil)
    }
    let source = EventTapInputSource(tapMaker: maker, primaryFrame: { Self.primary })
    #expect(source.start() == .started)
    #expect(source.start() == .started)
    #expect(made.withLock { $0 } == 1)
    #expect(source.recreate() == .started)
    #expect(made.withLock { $0 } == 2)
    var signals = source.signals.makeAsyncIterator()
    #expect(await signals.next() == .recreated(true))
    source.stop()
    source.stop()
    #expect(source.reenable() == false)
    #expect(source.start() == .started)
    #expect(made.withLock { $0 } == 3)
    source.stop()
  }

  // AC-050
  @Test func otherButtonsFiltered() throws {
    func mouse(_ type: CGEventType, _ button: CGMouseButton) throws -> CGEvent {
      try #require(
        CGEvent(
          mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: 100, y: 200),
          mouseButton: button))
    }
    func translate(_ type: CGEventType, _ event: CGEvent) -> InputEvent? {
      EventTapInputSource.translate(type: type, event: event, primaryFrame: Self.primary)
    }

    for type in [CGEventType.rightMouseDown, .rightMouseDragged, .rightMouseUp] {
      #expect(translate(type, try mouse(type, .right)) == nil, "\(type)")
    }
    for type in [CGEventType.otherMouseDown, .otherMouseDragged, .otherMouseUp] {
      #expect(translate(type, try mouse(type, .center)) == nil, "\(type)")
    }
    for type in [CGEventType.mouseMoved, .keyDown, .scrollWheel, .tapDisabledByTimeout] {
      #expect(translate(type, try mouse(.leftMouseDown, .left)) == nil, "\(type)")
    }

    let expected: [(CGEventType, InputKind)] = [
      (.leftMouseDown, .leftDown), (.leftMouseDragged, .leftDragged), (.leftMouseUp, .leftUp),
    ]
    for (type, kind) in expected {
      let event = try mouse(type, .left)
      event.flags = [.maskShift, .maskAlphaShift, .maskSecondaryFn, .maskControl]
      event.timestamp = 5_000_000_000
      event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: 4242)
      let input = try #require(translate(type, event))
      #expect(input.kind == kind)
      // CG space has its origin top-left; AppKit's is bottom-left of the primary display.
      #expect(input.point == CGPoint(x: 100, y: 700))
      #expect(input.flags == [.shift, .control])
      #expect(input.windowUnderPointer == WindowID(rawValue: 4242))
      #expect(input.time == 5.0)

      event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: 0)
      #expect(translate(type, event)?.windowUnderPointer == nil)
    }

    let flagsEvent = try mouse(.leftMouseDown, .left)
    flagsEvent.flags = [.maskShift, .maskAlphaShift, .maskSecondaryFn]
    let flagsInput = try #require(translate(.flagsChanged, flagsEvent))
    #expect(flagsInput.kind == .flagsChanged)
    #expect(flagsInput.flags == [.shift])
  }

  /// The callback body: tap-disabled types become signals, mouse events become `InputEvent`s, and the event is
  /// handed back untouched.
  @Test func callbackBoxYieldsSignalsAndEvents() async throws {
    let source = EventTapInputSource(tapMaker: TapMaker { _, _ in nil }, primaryFrame: { Self.primary })
    let box = source.callbackBox
    let down = try #require(
      CGEvent(
        mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: 10, y: 20),
        mouseButton: .left))
    let right = try #require(
      CGEvent(
        mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: CGPoint(x: 10, y: 20),
        mouseButton: .right))
    let flagsBefore = down.flags  // a new event may carry host flags (macOS 27 sets maskNonCoalesced)
    box.handle(type: .tapDisabledByTimeout, event: down)
    box.handle(type: .tapDisabledByUserInput, event: down)
    box.handle(type: .rightMouseDown, event: right)
    box.handle(type: .leftMouseDown, event: down)

    var signals = source.signals.makeAsyncIterator()
    #expect(await signals.next() == .disabledByTimeout)
    #expect(await signals.next() == .disabledByUserInput)
    var events = source.events.makeAsyncIterator()
    let first = await events.next()
    #expect(first?.kind == .leftDown)
    #expect(first?.point == CGPoint(x: 10, y: 880))
    #expect(down.flags == flagsBefore)  // not modified
  }

  /// T64: both streams are bounded for a stalled consumer. Past `dragLimit` queued drags the oldest drag goes, so
  /// the newest pointer positions get through; down, up and flagsChanged are never dropped and keep their order.
  /// Signals keep the newest `signalLimit`.
  @Test func streamsAreBoundedAndKeepEveryButtonAndModifierEvent() async {
    let source = EventTapInputSource(tapMaker: TapMaker { _, _ in nil }, primaryFrame: { Self.primary })
    func event(_ kind: InputKind, _ time: TimeInterval) -> InputEvent {
      InputEvent(kind: kind, point: .zero, flags: [], windowUnderPointer: nil, time: time)
    }
    let limit = EventTapInputSource.dragLimit
    let excess = 50
    let box = source.callbackBox
    box.events.push(event(.leftDown, 0))
    for t in 1...9 { box.events.push(event(.leftDragged, Double(t))) }
    box.events.push(event(.flagsChanged, 9.5))
    for t in 10...(limit + excess) { box.events.push(event(.leftDragged, Double(t))) }
    box.events.push(event(.flagsChanged, 1000))
    box.events.push(event(.leftUp, 1001))

    let expected =
      [event(.leftDown, 0), event(.flagsChanged, 9.5)]
      + ((excess + 1)...(limit + excess)).map { event(.leftDragged, Double($0)) }
      + [event(.flagsChanged, 1000), event(.leftUp, 1001)]
    var events = source.events.makeAsyncIterator()
    var got: [InputEvent] = []
    for _ in expected.indices {
      if let next = await events.next() { got.append(next) }
    }
    #expect(got == expected)

    // A consumer suspended on the empty queue gets the next push; cancelling it ends the stream.
    let waiting = Task { await events.next() }
    try? await Task.sleep(for: .milliseconds(20))
    box.events.push(event(.leftDown, 2000))
    #expect(await waiting.value == event(.leftDown, 2000))
    let buffer = InputBuffer(dragLimit: 1)
    let stream = buffer.stream()
    let cancelled = Task {
      var it = stream.makeAsyncIterator()
      return await it.next()
    }
    try? await Task.sleep(for: .milliseconds(20))
    cancelled.cancel()
    #expect(await cancelled.value == nil)
    buffer.push(event(.leftUp, 1))  // dropped: the buffer is finished

    for _ in 0..<5 { box.signals.yield(.recreated(true)) }
    for _ in 0..<EventTapInputSource.signalLimit { box.signals.yield(.disabledByTimeout) }
    var signals = source.signals.makeAsyncIterator()
    #expect(await signals.next() == .disabledByTimeout)
  }
}
