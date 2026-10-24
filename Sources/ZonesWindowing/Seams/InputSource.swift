import CoreGraphics
import Foundation
import ZonesCore

public enum InputKind: Hashable, Sendable { case leftDown, leftDragged, leftUp, flagsChanged }

public struct InputEvent: Hashable, Sendable {
  public var kind: InputKind
  public var point: CGPoint
  public var flags: ModifierSet
  public var windowUnderPointer: WindowID?
  public var time: TimeInterval
  public init(
    kind: InputKind, point: CGPoint, flags: ModifierSet, windowUnderPointer: WindowID?,
    time: TimeInterval
  ) {
    self.kind = kind
    self.point = point
    self.flags = flags
    self.windowUnderPointer = windowUnderPointer
    self.time = time
  }
}

public struct TapConfig: Hashable, Sendable {
  public var listenOnly: Bool
  public var mask: Set<InputKind>
  public init(listenOnly: Bool, mask: Set<InputKind>) {
    self.listenOnly = listenOnly
    self.mask = mask
  }
  /// AC-065: a listen-only tap over the four mouse and modifier events.
  public static let production = TapConfig(
    listenOnly: true, mask: [.leftDown, .leftDragged, .leftUp, .flagsChanged])
}

public enum TapStart: Hashable, Sendable { case started, unavailable }
public enum TapSignal: Hashable, Sendable { case disabledByTimeout, disabledByUserInput, recreated(Bool) }

/// Production: EventTapInputSource. Fake: FakeInputSource.
public protocol InputSource: Sendable {
  var config: TapConfig { get }
  func start() -> TapStart
  func stop()
  func reenable() -> Bool
  func recreate() -> TapStart
  var events: AsyncStream<InputEvent> { get }
  var signals: AsyncStream<TapSignal> { get }
}
