import ZonesCore

/// Turns a captured key-down into the pieces of a `Chord`. The key table is the Carbon registrar's own, run
/// backwards, so a key the recorder accepts is a key the registrar can bind.
public enum RecorderKeyMap {
  private static let keys: [Key] =
    (0...9).map { Key.digit($0) } + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { Key.letter(String($0)) }
    + [.arrowLeft, .arrowRight, .arrowUp, .arrowDown, .comma]

  private static let byCode: [UInt32: Key] = {
    var table: [UInt32: Key] = [:]
    for key in keys { if let code = CarbonKeyMap.keyCode(for: key) { table[code] = key } }
    return table
  }()

  /// The ANSI virtual key code's `Key`, or nil for a key Zones cannot bind.
  public static func key(forKeyCode code: UInt16) -> Key? { byCode[UInt32(code)] }

  /// The four modifiers in `NSEvent.modifierFlags.rawValue` / `CGEventFlags` bits; everything else is ignored.
  public static func modifiers(rawFlags: UInt64) -> ModifierSet { ModifierSet.masked(rawFlags) }

  /// What the recorder does with one key-down. Pure so the keyboard path (no trap) is testable headless.
  public enum Disposition: Hashable, Sendable {
    case startRecording, stopRecording, moveFocus(forward: Bool), capture(Chord), clear, reject, passThrough
  }

  private static let tab: UInt16 = 48
  private static let escape: UInt16 = 53
  private static let clearKeys: Set<UInt16> = [51, 117]  // Delete, Forward Delete
  private static let armKeys: Set<UInt16> = [49, 36, 76]  // Space, Return, keypad Enter

  /// Focus arrival never arms the recorder. Unarmed, Space or Return arms it and Tab or Shift-Tab move on, so a
  /// keyboard-only user can always pass through. Armed, Tab and Shift-Tab still move on (recording ends with
  /// focus), Escape disarms in place, a bare Delete or Forward Delete clears the shortcut (armed or not), and any other key is a chord or a rejected key.
  public static func disposition(keyCode: UInt16, rawFlags: UInt64, recording: Bool) -> Disposition {
    let mods = modifiers(rawFlags: rawFlags)
    if keyCode == tab, mods.isEmpty || mods == [.shift] { return .moveFocus(forward: mods.isEmpty) }
    if clearKeys.contains(keyCode), mods.isEmpty { return .clear }
    guard recording else {
      return mods.isEmpty && armKeys.contains(keyCode) ? .startRecording : .passThrough
    }
    if keyCode == escape { return .stopRecording }
    guard let key = key(forKeyCode: keyCode) else { return .reject }
    return .capture(Chord(key: key, modifiers: mods))
  }
}
