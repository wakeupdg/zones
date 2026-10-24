import Carbon.HIToolbox
import Foundation
import ZonesCore

/// Pure Key and modifier tables for Carbon `RegisterEventHotKey`; testable without Carbon.
enum CarbonKeyMap {
  private static let digitCodes: [UInt32] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]  // 0...9
  private static let letterCodes: [Character: UInt32] = [
    "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "Q": 12,
    "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32, "I": 34, "P": 35, "L": 37, "J": 38,
    "K": 40, "N": 45, "M": 46,
  ]

  /// ANSI virtual keycode, or nil for a digit outside 0...9 or a string that is not one known letter.
  static func keyCode(for key: Key) -> UInt32? {
    switch key {
    case .digit(let n): digitCodes.indices.contains(n) ? digitCodes[n] : nil
    case .letter(let s):
      // "ß".uppercased() is "SS": Character(String) would trap on more than one grapheme.
      guard s.count == 1, s.uppercased().count == 1, let c = s.uppercased().first else { return nil }
      return letterCodes[c]
    case .arrowLeft: 123
    case .arrowRight: 124
    case .arrowDown: 125
    case .arrowUp: 126
    case .comma: 43
    }
  }

  /// Carbon modifier bits: command 256, shift 512, option 2048, control 4096.
  static func modifiers(_ m: ModifierSet) -> UInt32 {
    var bits: UInt32 = 0
    if m.contains(.command) { bits |= 256 }
    if m.contains(.shift) { bits |= 512 }
    if m.contains(.option) { bits |= 2048 }
    if m.contains(.control) { bits |= 4096 }
    return bits
  }
}

/// Production `HotkeyRegistrar` over Carbon `RegisterEventHotKey` (ADR-0011). Hotkeys need no TCC grant
/// (ADR-0020). Wiring into the app is a later ticket. Intended to live for the whole process: the event
/// handler holds an unretained pointer to it.
@MainActor public final class CarbonHotkeyRegistrar: HotkeyRegistrar {
  public let presses: AsyncStream<ShortcutAction>

  private static let signature: OSType = 0x5A4F_4E45  // 'ZONE'
  private static let existsStatus: OSStatus = -9878  // eventHotKeyExistsErr

  private let continuation: AsyncStream<ShortcutAction>.Continuation
  private var refs: [ShortcutAction: EventHotKeyRef] = [:]
  private var chords: [ShortcutAction: Chord] = [:]
  private var handler: EventHandlerRef?

  public init() {
    (presses, continuation) = AsyncStream.makeStream(of: ShortcutAction.self)
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let userData = Unmanaged.passUnretained(self).toOpaque()
    var installed: EventHandlerRef?
    let status = InstallEventHandler(
      GetApplicationEventTarget(), Self.callback, 1, &spec, userData, &installed)
    if status == noErr { handler = installed }
  }

  /// Stable id per action: its `allCases` index plus one.
  private static func id(for action: ShortcutAction) -> UInt32? {
    ShortcutAction.allCases.firstIndex(of: action).map { UInt32($0 + 1) }
  }

  private static func action(forID id: UInt32) -> ShortcutAction? {
    let i = Int(id) - 1
    return ShortcutAction.allCases.indices.contains(i) ? ShortcutAction.allCases[i] : nil
  }

  private static let callback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
      event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
      MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr, hotKeyID.signature == CarbonHotkeyRegistrar.signature else {
      return OSStatus(eventNotHandledErr)
    }
    let registrar = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(userData)
    // Application-target events are delivered on the main thread.
    MainActor.assumeIsolated {
      if let action = action(forID: hotKeyID.id) { registrar.takeUnretainedValue().continuation.yield(action) }
    }
    return noErr
  }

  public func register(_ chord: Chord, for action: ShortcutAction) -> HotkeyRegistration {
    guard let code = CarbonKeyMap.keyCode(for: chord.key), let id = Self.id(for: action) else {
      return .invalid
    }
    if chords[action] == chord, refs[action] != nil { return .registered }
    var newRef: EventHotKeyRef?
    // Register the new hotkey first; the old one stays live if this fails.
    let status = RegisterEventHotKey(
      code, CarbonKeyMap.modifiers(chord.modifiers), EventHotKeyID(signature: Self.signature, id: id),
      GetApplicationEventTarget(), 0, &newRef)
    guard status == noErr, let newRef else {
      return status == Self.existsStatus ? .inUse : .invalid
    }
    if let old = refs[action] { UnregisterEventHotKey(old) }
    refs[action] = newRef
    chords[action] = chord
    return .registered
  }

  public func unregister(_ action: ShortcutAction) {
    if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
    chords[action] = nil
  }

  public func bound(_ action: ShortcutAction) -> Chord? { chords[action] }
}
