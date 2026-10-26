import Foundation
import ZonesCore
import ZonesWindowing
import os

/// A scriptable `DisplayProvider`. Once the queue drains, `snapshot()` repeats the last snapshot it
/// returned (a topology stays put until it changes); before any snapshot it returns no displays.
public final class FakeDisplayProvider: DisplayProvider, Sendable {
  public enum Call: Hashable, Sendable { case snapshot }

  public enum Response: Sendable { case snapshot(TopologySnapshot) }

  private static let empty = TopologySnapshot(displays: [], separateSpaces: true, primaryFrame: .zero)

  private let queue = ResponseQueue<Response>()
  private let recorder: CallRecorder<Call>
  private let changeStream = StreamBox<RawDisplayChange>()
  private let last = OSAllocatedUnfairLock<TopologySnapshot?>(initialState: nil)

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

  public func emit(_ change: RawDisplayChange) { changeStream.emit(change) }

  public func reset() {
    queue.reset()
    recorder.reset()
    changeStream.reset()
    last.withLock { $0 = nil }
  }

  public var changes: AsyncStream<RawDisplayChange> { changeStream.stream }

  public func snapshot() -> TopologySnapshot {
    recorder.record(.snapshot)
    let next = queue.take { if case .snapshot(let s) = $0 { s } else { nil } }
    return last.withLock { held in
      if let next { held = next }
      return held ?? Self.empty
    }
  }
}
