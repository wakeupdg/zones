import CoreGraphics
import Foundation
import ZonesCore
import os

/// Creates the Mach port behind the event tap. `userInfo` is the callback box. A nil result is the "no
/// permission" case (ADR-0020), never a crash. Tests inject a maker so no live tap is created.
struct TapMaker: Sendable {
  var make: @Sendable (TapConfig, UnsafeMutableRawPointer) -> CFMachPort?
}

/// What the `@convention(c)` tap callback reaches through `userInfo`. Immutable and `Sendable` by construction.
final class TapCallbackBox: Sendable {
  let events: AsyncStream<InputEvent>.Continuation
  let signals: AsyncStream<TapSignal>.Continuation
  let primaryFrame: @Sendable () -> CGRect

  init(
    events: AsyncStream<InputEvent>.Continuation, signals: AsyncStream<TapSignal>.Continuation,
    primaryFrame: @escaping @Sendable () -> CGRect
  ) {
    self.events = events
    self.signals = signals
    self.primaryFrame = primaryFrame
  }

  /// The callback body, O(1): turn the event into a value and yield it. Never consumes or modifies `event`, and
  /// never re-enables the tap here: `TapRecovery` decides, and the driver calls `reenable()` (AC-011).
  func handle(type: CGEventType, event: CGEvent) {
    switch type {
    case .tapDisabledByTimeout: signals.yield(.disabledByTimeout)
    case .tapDisabledByUserInput: signals.yield(.disabledByUserInput)
    default:
      if let input = EventTapInputSource.translate(type: type, event: event, primaryFrame: primaryFrame()) {
        events.yield(input)
      }
    }
  }
}

extension TapMaker {
  /// A session-level tap at the tail of the chain, serviced by `eventTapCallback`.
  static let live = TapMaker { config, info in
    CGEvent.tapCreate(
      tap: .cgSessionEventTap, place: .tailAppendEventTap,
      options: config.listenOnly ? .listenOnly : .defaultTap,
      eventsOfInterest: EventTapInputSource.cgEventMask(for: config), callback: eventTapCallback,
      userInfo: info)
  }
}

/// `@convention(c)`: no captures, so state arrives through `userInfo`. Listen-only taps ignore the returned
/// event, but it is always handed back unretained and unmodified (AC-066).
private func eventTapCallback(
  _ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ info: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  if let info {
    Unmanaged<TapCallbackBox>.fromOpaque(info).takeUnretainedValue().handle(type: type, event: event)
  }
  return Unmanaged.passUnretained(event)
}

/// Production `InputSource` over a listen-only `CGEvent` tap on its own thread (AC-065). The tap never consumes
/// or modifies an event (AC-066); recovery decisions belong to `TapRecovery`, which the driver feeds from
/// `signals` before calling `reenable()` or `recreate()`.
public final class EventTapInputSource: InputSource, Sendable {
  public let config: TapConfig
  public let events: AsyncStream<InputEvent>
  public let signals: AsyncStream<TapSignal>

  let tapMaker: TapMaker
  private let box: TapCallbackBox
  var callbackBox: TapCallbackBox { box }

  /// The live tap and the thread that serves it. Present between a successful bring-up and teardown.
  private struct Runtime {
    var tap: CFMachPort
    var runLoop: CFRunLoop
    var finished: DispatchSemaphore
  }

  private struct State {
    /// Handed to the tap thread before it starts; consumed there.
    var pendingTap: CFMachPort?
    var runLoop: CFRunLoop?
    var runtime: Runtime?
  }

  private let state = OSAllocatedUnfairLock(uncheckedState: State())
  /// Serializes start, stop and recreate so two callers cannot bring up two taps.
  private let lifecycle = OSAllocatedUnfairLock()

  /// `primaryFrame` runs on the tap thread and must be safe to call from any thread.
  public convenience init(primaryFrame: @escaping @Sendable () -> CGRect) {
    self.init(tapMaker: .live, primaryFrame: primaryFrame)
  }

  init(
    config: TapConfig = .production, tapMaker: TapMaker, primaryFrame: @escaping @Sendable () -> CGRect
  ) {
    self.config = config
    self.tapMaker = tapMaker
    let (events, eventsContinuation) = AsyncStream<InputEvent>.makeStream()
    let (signals, signalsContinuation) = AsyncStream<TapSignal>.makeStream()
    self.events = events
    self.signals = signals
    box = TapCallbackBox(events: eventsContinuation, signals: signalsContinuation, primaryFrame: primaryFrame)
  }

  deinit {
    teardown()
    box.events.finish()
    box.signals.finish()
  }

  public func start() -> TapStart {
    lifecycle.withLock { bringUp() }
  }

  public func stop() {
    lifecycle.withLock { teardown() }
  }

  public func reenable() -> Bool {
    guard let tap = state.withLockUnchecked({ $0.runtime?.tap }) else { return false }
    CGEvent.tapEnable(tap: tap, enable: true)
    return CGEvent.tapIsEnabled(tap: tap)
  }

  public func recreate() -> TapStart {
    lifecycle.withLock {
      teardown()
      let result = bringUp()
      box.signals.yield(.recreated(result == .started))
      return result
    }
  }

  // MARK: Lifecycle

  /// Creates the tap and its thread. Idempotent while a tap is live. Callers hold `lifecycle`.
  private func bringUp() -> TapStart {
    if state.withLockUnchecked({ $0.runtime != nil }) { return .started }
    guard let tap = tapMaker.make(config, Unmanaged.passUnretained(box).toOpaque()) else {
      return .unavailable
    }
    state.withLockUnchecked { $0.pendingTap = tap }
    let ready = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let thread = Thread { [state] in
      let runLoop = CFRunLoopGetCurrent()!
      let source = state.withLockUnchecked { s -> CFRunLoopSource? in
        defer { s.pendingTap = nil }
        return s.pendingTap.flatMap { CFMachPortCreateRunLoopSource(nil, $0, 0) }
      }
      if let source { CFRunLoopAddSource(runLoop, source, .commonModes) }
      state.withLockUnchecked { $0.runLoop = runLoop }
      // Signalled from inside the loop, so a later CFRunLoopStop cannot arrive before the loop is running.
      CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { ready.signal() }
      CFRunLoopRun()
      if let source {
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CFRunLoopSourceInvalidate(source)
      }
      finished.signal()
    }
    thread.name = "Zones.EventTap"
    thread.qualityOfService = .userInteractive
    thread.start()
    ready.wait()
    state.withLockUnchecked { s in
      s.runtime = Runtime(tap: tap, runLoop: s.runLoop!, finished: finished)
      s.runLoop = nil
    }
    CGEvent.tapEnable(tap: tap, enable: true)
    return .started
  }

  /// Invalidates the port (a merely disabled tap stays registered with the window server), stops the thread and
  /// waits for it. Callers hold `lifecycle`, or are `deinit`.
  private func teardown() {
    guard let runtime = state.withLockUnchecked({ s -> Runtime? in
      defer { s.runtime = nil }
      return s.runtime
    }) else { return }
    CGEvent.tapEnable(tap: runtime.tap, enable: false)
    CFMachPortInvalidate(runtime.tap)
    CFRunLoopStop(runtime.runLoop)
    CFRunLoopWakeUp(runtime.runLoop)
    runtime.finished.wait()
  }

  // MARK: Translation

  /// Pure. Left down, dragged, up and flagsChanged only: right and other buttons (and anything else) give nil.
  /// `CGEvent.location` has its origin top-left, which is AX space, so `CoordinateSpace` flips it to AppKit.
  static func translate(type: CGEventType, event: CGEvent, primaryFrame: CGRect) -> InputEvent? {
    let kind: InputKind
    switch type {
    case .leftMouseDown: kind = .leftDown
    case .leftMouseDragged: kind = .leftDragged
    case .leftMouseUp: kind = .leftUp
    case .flagsChanged: kind = .flagsChanged
    default: return nil
    }
    let point = CoordinateSpace.appKitRect(CGRect(origin: event.location, size: .zero), primaryFrame: primaryFrame)
      .origin
    let windowField = event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
    let window = UInt32(exactly: windowField).flatMap { $0 == 0 ? nil : WindowID(rawValue: $0) }
    return InputEvent(
      kind: kind, point: point, flags: ModifierSet.masked(event.flags.rawValue), windowUnderPointer: window,
      time: Double(event.timestamp) / 1_000_000_000)
  }

  // MARK: Mask

  /// The mask has one bit per `CGEventType` in `config.mask`; nothing else is ever observed.
  static func cgEventMask(for config: TapConfig) -> CGEventMask {
    config.mask.reduce(CGEventMask(0)) { mask, kind in
      mask | (1 << CGEventMask(cgType(for: kind).rawValue))
    }
  }

  static func cgType(for kind: InputKind) -> CGEventType {
    switch kind {
    case .leftDown: .leftMouseDown
    case .leftDragged: .leftMouseDragged
    case .leftUp: .leftMouseUp
    case .flagsChanged: .flagsChanged
    }
  }
}
