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
      s.count == 1 ? letterCodes[Character(s.uppercased())] : nil
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
