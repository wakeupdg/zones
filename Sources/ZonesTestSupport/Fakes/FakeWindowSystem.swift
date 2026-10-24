import CoreGraphics
import Foundation
import ZonesCore
import ZonesWindowing
import os

// MARK: Shared helpers for every fake in Fakes/

/// FIFO of scripted responses. `take` removes the first response the extractor accepts, so one
/// fake can hold responses for several methods in the order the test enqueued them.
final class ResponseQueue<Response: Sendable>: Sendable {
  private let items = OSAllocatedUnfairLock(initialState: [Response]())

  func enqueue(_ response: Response) { items.withLock { $0.append(response) } }

  func take<Value>(_ extract: (Response) -> Value?) -> Value? {
    items.withLockUnchecked { all in
      for (index, response) in all.enumerated() {
        if let value = extract(response) {
          all.remove(at: index)
          return value
        }
      }
      return nil
    }
  }

  func reset() { items.withLock { $0.removeAll() } }
}

/// The typed call log plus latency, which runs on the injected `FakeClock`.
/// `calls` records each call when it is made; `completed` records it once `latency` seconds of fake
/// time have passed. With latency 0 both lists move together. The seam methods are synchronous, so
/// latency delays completion (observable here), never the returned value.
final class CallRecorder<Call: Sendable>: Sendable {
  private struct State {
    var latency: TimeInterval = 0
    var calls: [Call] = []
    var completed: [Call] = []
    var timers: [TimerHandle] = []
  }

  private let clock: FakeClock
  private let state = OSAllocatedUnfairLock(initialState: State())

  init(clock: FakeClock) { self.clock = clock }

  var latency: TimeInterval {
    get { state.withLock { $0.latency } }
    set { state.withLock { $0.latency = newValue } }
  }
  var calls: [Call] { state.withLock { $0.calls } }
  var completed: [Call] { state.withLock { $0.completed } }
  var inFlight: Int { state.withLock { $0.calls.count - $0.completed.count } }

  func record(_ call: Call) {
    let delay = state.withLock { s -> TimeInterval in
      s.calls.append(call)
      if s.latency <= 0 { s.completed.append(call) }
      return s.latency
    }
    guard delay > 0 else { return }
    let handle = clock.schedule(.frameSample, after: delay, repeats: false) { [self] in
      state.withLock { $0.completed.append(call) }
    }
    state.withLock { $0.timers.append(handle) }
  }

  /// Clears both logs, cancels pending completions and puts latency back to 0.
  func reset() {
    let timers = state.withLock { s -> [TimerHandle] in
      let pending = s.timers
      s = State()
      return pending
    }
    for handle in timers { clock.cancel(handle) }
  }
}

/// Owns an `AsyncStream` and its continuation. `reset()` finishes the current stream and starts a new one.
final class StreamBox<Element: Sendable>: Sendable {
  private struct State {
    var stream: AsyncStream<Element>
    var continuation: AsyncStream<Element>.Continuation
  }

  private let state: OSAllocatedUnfairLock<State>

  init() {
    let (stream, continuation) = AsyncStream<Element>.makeStream()
    state = OSAllocatedUnfairLock(initialState: State(stream: stream, continuation: continuation))
  }

  var stream: AsyncStream<Element> { state.withLock { $0.stream } }

  func emit(_ element: Element) {
    let continuation = state.withLock { $0.continuation }
    continuation.yield(element)
  }

  func reset() {
    let old = state.withLock { s -> AsyncStream<Element>.Continuation in
      let previous = s.continuation
      let (stream, continuation) = AsyncStream<Element>.makeStream()
      s.stream = stream
      s.continuation = continuation
      return previous
    }
    old.finish()
  }
}

// MARK: FakeWindowSystem

/// A scriptable `WindowSystem`. Seam methods are `@WindowActor`; the test-facing surface
/// (`enqueue`, `calls`, `latency`, `reset`, `emit`) can be used from any context.
public final class FakeWindowSystem: WindowSystem, Sendable {
  public enum Call: Hashable, Sendable {
    case setTimeouts(perApp: TimeInterval, processWide: TimeInterval)
    case elementAt(CGPoint), windowsOf(pid_t), focusedWindow
    case frame(WindowHandle), frames([WindowHandle]), facts(WindowHandle)
    case setPosition(CGPoint, WindowHandle), setSize(CGSize, WindowHandle)
    case enhancedUI(pid_t), setEnhancedUI(Bool, pid_t), trivialRead, notices
  }

  /// One scripted result. Each case answers the method of the same name; an empty queue for that
  /// method falls back to a neutral default (`.elementGone`, `.ok`, `nil`, `[]`, `[:]`).
  public enum Response: Sendable {
    case element(WindowHandle?), windows([WindowHandle]), focused(WindowHandle?)
    case frame(AXRead<CGRect>), frames([WindowKey: AXRead<CGRect>]), facts(AXRead<WindowFacts>)
    case position(AXStatus), size(AXStatus)
    case enhancedUI(AXRead<Bool?>), setEnhancedUI(AXStatus), trivialRead(AXStatus)
  }

  private let queue = ResponseQueue<Response>()
  private let recorder: CallRecorder<Call>
  private let noticeStream = StreamBox<AXNotice>()

  public init(clock: FakeClock) { recorder = CallRecorder(clock: clock) }

  public func enqueue(_ response: Response) { queue.enqueue(response) }
  public var calls: [Call] { recorder.calls }
  /// Calls whose `latency` has elapsed on the clock.
  public var completed: [Call] { recorder.completed }
  public var inFlight: Int { recorder.inFlight }
  public var latency: TimeInterval {
    get { recorder.latency }
    set { recorder.latency = newValue }
  }
  public func emit(_ notice: AXNotice) { noticeStream.emit(notice) }

  public func reset() {
    queue.reset()
    recorder.reset()
    noticeStream.reset()
  }

  @WindowActor public func setTimeouts(perApp: TimeInterval, processWide: TimeInterval) {
    recorder.record(.setTimeouts(perApp: perApp, processWide: processWide))
  }

  @WindowActor public func element(at point: CGPoint) -> WindowHandle? {
    recorder.record(.elementAt(point))
    return queue.take { if case .element(let h) = $0 { .some(h) } else { nil } } ?? nil
  }

  @WindowActor public func windows(of pid: pid_t) -> [WindowHandle] {
    recorder.record(.windowsOf(pid))
    return queue.take { if case .windows(let hs) = $0 { hs } else { nil } } ?? []
  }

  @WindowActor public func focusedWindow() -> WindowHandle? {
    recorder.record(.focusedWindow)
    return queue.take { if case .focused(let h) = $0 { .some(h) } else { nil } } ?? nil
  }

  @WindowActor public func frame(_ h: WindowHandle) -> AXRead<CGRect> {
    recorder.record(.frame(h))
    return queue.take { if case .frame(let r) = $0 { r } else { nil } } ?? .elementGone
  }

  @WindowActor public func frames(_ hs: [WindowHandle]) -> [WindowKey: AXRead<CGRect>] {
    recorder.record(.frames(hs))
    return queue.take { if case .frames(let r) = $0 { r } else { nil } } ?? [:]
  }

  @WindowActor public func facts(_ h: WindowHandle) -> AXRead<WindowFacts> {
    recorder.record(.facts(h))
    return queue.take { if case .facts(let r) = $0 { r } else { nil } } ?? .elementGone
  }

  @WindowActor public func setPosition(_ p: CGPoint, _ h: WindowHandle) -> AXStatus {
    recorder.record(.setPosition(p, h))
    return queue.take { if case .position(let s) = $0 { s } else { nil } } ?? .ok
  }

  @WindowActor public func setSize(_ s: CGSize, _ h: WindowHandle) -> AXStatus {
    recorder.record(.setSize(s, h))
    return queue.take { if case .size(let r) = $0 { r } else { nil } } ?? .ok
  }

  @WindowActor public func enhancedUI(pid: pid_t) -> AXRead<Bool?> {
    recorder.record(.enhancedUI(pid))
    return queue.take { if case .enhancedUI(let r) = $0 { r } else { nil } } ?? .value(nil)
  }

  @WindowActor public func setEnhancedUI(_ on: Bool, pid: pid_t) -> AXStatus {
    recorder.record(.setEnhancedUI(on, pid))
    return queue.take { if case .setEnhancedUI(let s) = $0 { s } else { nil } } ?? .ok
  }

  @WindowActor public func trivialRead() -> AXStatus {
    recorder.record(.trivialRead)
    return queue.take { if case .trivialRead(let s) = $0 { s } else { nil } } ?? .ok
  }

  public func notices() -> AsyncStream<AXNotice> {
    recorder.record(.notices)
    return noticeStream.stream
  }
}
