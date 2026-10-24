import Foundation
import ZonesCore

public enum ShortcutStoreEvent: Hashable, Sendable {
  case set(ShortcutAction, Chord?)
  case registration(ShortcutAction, HotkeyRegistration)
  case permission(granted: Bool)
  case reducerIdle(Bool)
  case launch
}

public enum ShortcutStoreEffect: Hashable, Sendable {
  case register(Chord, ShortcutAction)
  case unregister(ShortcutAction)
  case failed(ShortcutAction, HotkeyRegistration)
  case persist([Shortcut])
}

public struct ShortcutStoreState: Hashable, Sendable {
  public var shortcuts: [Shortcut]
  public var registered: Set<ShortcutAction>
  public var granted: Bool
  public var idle: Bool
  public var queued: [ShortcutStoreEvent]
  /// An unconfirmed chord awaiting its registration result; `shortcuts` still holds the old one.
  public var pending: [ShortcutAction: Chord]

  public init(
    shortcuts: [Shortcut] = ShortcutRules.defaults, registered: Set<ShortcutAction> = [], granted: Bool = false,
    idle: Bool = true, queued: [ShortcutStoreEvent] = [], pending: [ShortcutAction: Chord] = [:]
  ) {
    self.shortcuts = shortcuts
    self.registered = registered
    self.granted = granted
    self.idle = idle
    self.queued = queued
    self.pending = pending
  }

  func chord(of action: ShortcutAction) -> Chord? { shortcuts.first { $0.action == action }?.chord }
  func eligible(_ action: ShortcutAction) -> Bool { !action.isWindowAction || granted }
}

public enum ShortcutStore {
  public static func reduce(_ s: ShortcutStoreState, _ e: ShortcutStoreEvent) -> (ShortcutStoreState, [ShortcutStoreEffect]) {
    var s = s
    var effects: [ShortcutStoreEffect] = []
    switch e {
    case .launch:
      effects = registrations(s) { _ in true }
    case .permission(let granted):
      guard granted != s.granted else { return (s, []) }
      s.granted = granted
      if granted {
        effects = registrations(s) { $0.isWindowAction }
      } else {
        for a in ShortcutAction.allCases where a.isWindowAction && s.registered.contains(a) {
          s.registered.remove(a)
          effects.append(.unregister(a))
        }
      }
    case .registration(let a, .registered):
      s.registered.insert(a)
    case .set, .registration, .reducerIdle:
      break
    }
    return (s, effects)
  }

  /// `register` effects, in `allCases` order, for eligible actions with a chord that are not yet registered.
  private static func registrations(_ s: ShortcutStoreState, where include: (ShortcutAction) -> Bool)
    -> [ShortcutStoreEffect]
  {
    ShortcutAction.allCases.compactMap { a in
      guard include(a), s.eligible(a), !s.registered.contains(a), let chord = s.chord(of: a) else { return nil }
      return .register(chord, a)
    }
  }
}
