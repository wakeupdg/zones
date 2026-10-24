import Foundation
import ZonesCore
import ZonesWindowing
import os

/// A `@MainActor` scriptable `LoginItemService`. With nothing queued, `status()` reports the tracked
/// status: `.notRegistered` at first, `.enabled` after a successful `register()`, `.notRegistered`
/// after `unregister()`. A queued `.status` answers one `status()` call; a queued `.register` or
/// `.unregister` error makes that call throw and leaves the tracked status alone.
public final class FakeLoginItemService: LoginItemService, Sendable {
  public enum Call: Hashable, Sendable { case status, register, unregister, openLoginItemsSettings }

  public enum Response: Sendable {
    case status(LoginItemStatus), register(LoginItemError), unregister(LoginItemError)
  }

  private let queue = ResponseQueue<Response>()
  private let recorder: CallRecorder<Call>
  private let tracked = OSAllocatedUnfairLock(initialState: LoginItemStatus.notRegistered)

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

  public func reset() {
    queue.reset()
    recorder.reset()
    tracked.withLock { $0 = .notRegistered }
  }

  @MainActor public func status() -> LoginItemStatus {
    recorder.record(.status)
    if let scripted = queue.take({ if case .status(let s) = $0 { s } else { nil } }) { return scripted }
    return tracked.withLock { $0 }
  }

  @MainActor public func register() throws(LoginItemError) {
    recorder.record(.register)
    if let error = queue.take({ if case .register(let e) = $0 { e } else { nil } }) { throw error }
    tracked.withLock { $0 = .enabled }
  }

  @MainActor public func unregister() throws(LoginItemError) {
    recorder.record(.unregister)
    if let error = queue.take({ if case .unregister(let e) = $0 { e } else { nil } }) { throw error }
    tracked.withLock { $0 = .notRegistered }
  }

  @MainActor public func openLoginItemsSettings() { recorder.record(.openLoginItemsSettings) }
}
