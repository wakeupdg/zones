import CoreGraphics
import Foundation
import ZonesCore
import ZonesWindowing

/// A scriptable `WindowEnumerator`. An empty queue for a method returns `[]`.
public final class FakeWindowEnumerator: WindowEnumerator, Sendable {
  public enum Call: Hashable, Sendable {
    case onScreenWindows, windows(ids: [WindowID]), candidates(under: CGPoint, hint: WindowID?)
  }

  /// One scripted list, answering the method of the same name.
  public enum Response: Sendable {
    case onScreen([WindowRef]), windows([WindowRef]), candidates([WindowRef])
  }

  private let queue = ResponseQueue<Response>()
  private let recorder: CallRecorder<Call>

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
  }

  public func onScreenWindows() -> [WindowRef] {
    recorder.record(.onScreenWindows)
    return queue.take { if case .onScreen(let l) = $0 { l } else { nil } } ?? []
  }

  public func windows(ids: [WindowID]) -> [WindowRef] {
    recorder.record(.windows(ids: ids))
    return queue.take { if case .windows(let l) = $0 { l } else { nil } } ?? []
  }

  public func candidates(under point: CGPoint, hint: WindowID?) -> [WindowRef] {
    recorder.record(.candidates(under: point, hint: hint))
    return queue.take { if case .candidates(let l) = $0 { l } else { nil } } ?? []
  }
}
