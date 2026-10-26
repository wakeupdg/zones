import Foundation
import ZonesCore
import ZonesWindowing

/// A scriptable `InputSource`. `emit(_:)` pushes onto `events` or `signals`.
/// Empty-queue defaults: `start()` and `recreate()` give `.started`, `reenable()` gives `true`.
public final class FakeInputSource: InputSource, Sendable {
  public enum Call: Hashable, Sendable { case start, stop, reenable, recreate }

  public enum Response: Sendable {
    case start(TapStart), reenable(Bool), recreate(TapStart)
  }

  public let config: TapConfig
  private let queue = ResponseQueue<Response>()
  private let recorder: CallRecorder<Call>
  private let eventStream = StreamBox<InputEvent>()
  private let signalStream = StreamBox<TapSignal>()

  public init(clock: FakeClock, config: TapConfig = .production) {
    self.config = config
    recorder = CallRecorder(clock: clock)
  }

  public func enqueue(_ response: Response) { queue.enqueue(response) }
  public var calls: [Call] { recorder.calls }
  /// Calls whose `latency` has elapsed on the clock.
  public var completed: [Call] { recorder.completed }
  public var inFlight: Int { recorder.inFlight }
  public var latency: TimeInterval {
    get { recorder.latency }
    set { recorder.latency = newValue }
  }

  public func emit(_ event: InputEvent) { eventStream.emit(event) }
  public func emit(_ signal: TapSignal) { signalStream.emit(signal) }

  /// Clears queue and log, and finishes the current streams (new ones start empty).
  public func reset() {
    queue.reset()
    recorder.reset()
    eventStream.reset()
    signalStream.reset()
  }

  public var events: AsyncStream<InputEvent> { eventStream.stream }
  public var signals: AsyncStream<TapSignal> { signalStream.stream }

  public func start() -> TapStart {
    recorder.record(.start)
    return queue.take { if case .start(let r) = $0 { r } else { nil } } ?? .started
  }

  public func stop() { recorder.record(.stop) }

  public func reenable() -> Bool {
    recorder.record(.reenable)
    return queue.take { if case .reenable(let r) = $0 { r } else { nil } } ?? true
  }

  public func recreate() -> TapStart {
    recorder.record(.recreate)
    return queue.take { if case .recreate(let r) = $0 { r } else { nil } } ?? .started
  }
}
