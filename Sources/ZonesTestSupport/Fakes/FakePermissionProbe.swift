import Foundation
import ZonesCore
import ZonesWindowing
import os

/// A scriptable `PermissionProbe`. `isTrusted()` answers the queue in order, then repeats the last
/// answer (initially `false`). `launchedAtLogin` is a plain settable value, not logged.
public final class FakePermissionProbe: PermissionProbe, Sendable {
  public enum Call: Hashable, Sendable { case isTrusted, openAccessibilitySettings }

  public enum Response: Sendable { case trusted(Bool) }

  private struct State {
    var trusted = false
    var launchedAtLogin = false
  }

  private let queue = ResponseQueue<Response>()
  private let recorder: CallRecorder<Call>
  private let state = OSAllocatedUnfairLock(initialState: State())

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

  public var launchedAtLogin: Bool {
    get { state.withLock { $0.launchedAtLogin } }
    set { state.withLock { $0.launchedAtLogin = newValue } }
  }

  public func reset() {
    queue.reset()
    recorder.reset()
    state.withLock { $0 = State() }
  }

  public func isTrusted() -> Bool {
    recorder.record(.isTrusted)
    let next = queue.take { if case .trusted(let t) = $0 { t } else { nil } }
    return state.withLock { s in
      if let next { s.trusted = next }
      return s.trusted
    }
  }

  @MainActor public func openAccessibilitySettings() { recorder.record(.openAccessibilitySettings) }
}
