import Foundation
import ZonesCore
import ZonesWindowing
import os

/// A `@MainActor` scriptable `HotkeyRegistrar`. A `.registered` result (the default when the queue is
/// empty) binds the chord, so `bound(_:)` returns it; `.inUse` and `.invalid` bind nothing.
public final class FakeHotkeyRegistrar: HotkeyRegistrar, Sendable {
  public enum Call: Hashable, Sendable {
    case register(Chord, ShortcutAction), unregister(ShortcutAction), bound(ShortcutAction)
  }

  public enum Response: Sendable { case registration(HotkeyRegistration) }

  private let queue = ResponseQueue<Response>()
  private let recorder: CallRecorder<Call>
  private let bindings = OSAllocatedUnfairLock(initialState: [ShortcutAction: Chord]())
  private let pressStream = StreamBox<ShortcutAction>()

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

  /// Simulates the user pressing a bound hotkey.
  public func press(_ action: ShortcutAction) { pressStream.emit(action) }

  public func reset() {
    queue.reset()
    recorder.reset()
    pressStream.reset()
    bindings.withLock { $0.removeAll() }
  }

  public var presses: AsyncStream<ShortcutAction> { pressStream.stream }

  @MainActor public func register(_ chord: Chord, for action: ShortcutAction) -> HotkeyRegistration {
    recorder.record(.register(chord, action))
    let result =
      queue.take { if case .registration(let r) = $0 { r } else { nil } } ?? .registered
    if result == .registered { bindings.withLock { $0[action] = chord } }
    return result
  }

  @MainActor public func unregister(_ action: ShortcutAction) {
    recorder.record(.unregister(action))
    bindings.withLock { _ = $0.removeValue(forKey: action) }
  }

  @MainActor public func bound(_ action: ShortcutAction) -> Chord? {
    recorder.record(.bound(action))
    return bindings.withLock { $0[action] }
  }
}
