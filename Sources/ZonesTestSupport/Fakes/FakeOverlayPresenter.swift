import Foundation
import ZonesCore
import ZonesWindowing
import os

/// A `@MainActor` recorder for `OverlayPresenter`. Its methods return nothing, so there is no
/// response queue; `isShown` is derived: `show` turns it on, `hide` and `orderOut` turn it off.
public final class FakeOverlayPresenter: OverlayPresenter, Sendable {
  public enum Call: Hashable, Sendable {
    case show(OverlayScene), highlight(Highlight), hide, reassert, orderOut, resize(TopologySnapshot)
  }

  private let recorder: CallRecorder<Call>
  private let shown = OSAllocatedUnfairLock(initialState: false)

  public init(clock: FakeClock) { recorder = CallRecorder(clock: clock) }

  public var calls: [Call] { recorder.calls }
  /// Calls whose `latency` has elapsed on the clock.
  public var completed: [Call] { recorder.completed }
  public var inFlight: Int { recorder.inFlight }
  public var latency: TimeInterval {
    get { recorder.latency }
    set { recorder.latency = newValue }
  }
  public var isShown: Bool { shown.withLock { $0 } }

  public func reset() {
    recorder.reset()
    shown.withLock { $0 = false }
  }

  @MainActor public func show(_ scene: OverlayScene) {
    recorder.record(.show(scene))
    shown.withLock { $0 = true }
  }

  @MainActor public func highlight(_ h: Highlight) { recorder.record(.highlight(h)) }

  @MainActor public func hide() {
    recorder.record(.hide)
    shown.withLock { $0 = false }
  }

  @MainActor public func reassert() { recorder.record(.reassert) }

  @MainActor public func orderOut() {
    recorder.record(.orderOut)
    shown.withLock { $0 = false }
  }

  @MainActor public func resize(to snapshot: TopologySnapshot) { recorder.record(.resize(snapshot)) }
}
