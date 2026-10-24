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
}
