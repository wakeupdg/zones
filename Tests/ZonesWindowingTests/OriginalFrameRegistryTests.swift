import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

/// Original Frame registry: a pure value type, so every test drives it directly (ADR-0009 amended).
@Suite struct OriginalFrameRegistryTests {
  static let w1 = WindowKey(pid: 100, elementHash: 1)
  static let w2 = WindowKey(pid: 100, elementHash: 2)
  static let frameA = CGRect(x: 10, y: 20, width: 600, height: 400)
  static let frameB = CGRect(x: 300, y: 300, width: 500, height: 300)
  static let display = DisplayKey.uuid("11111111-1111-4111-8111-111111111111")

  /// AC-089: first capture wins on both paths; a later Snap never overwrites.
  @Test func firstSnapCapturesPerPath() {
    var registry = OriginalFrameRegistry()

    // Mouse path: the mouse-down frame of the resolved window.
    let mouse = OriginalFrameEntry(key: Self.w1, frame: Self.frameA, via: .mouse)
    let first = registry.capture(mouse)
    #expect(first)
    #expect(registry.entry(Self.w1) == mouse)

    // A second applied Snap offers a different frame: refused, entry unchanged.
    let later = OriginalFrameEntry(key: Self.w1, frame: Self.frameB, via: .mouse)
    let second = registry.capture(later)
    #expect(!second)
    #expect(registry.entry(Self.w1) == mouse)
    let otherPath = registry.capture(
      OriginalFrameEntry(key: Self.w1, frame: Self.frameB, via: .keyboard))
    #expect(!otherPath)
    #expect(registry.entry(Self.w1)?.via == .mouse)

    // Keyboard path: the pre-write read-back frame, tagged keyboard.
    let keyboard = OriginalFrameEntry(key: Self.w2, frame: Self.frameB, via: .keyboard)
    let keyboardFirst = registry.capture(keyboard)
    #expect(keyboardFirst)
    #expect(registry.entry(Self.w2) == keyboard)
    #expect(registry.entry(Self.w2)?.via == .keyboard)
    let keyboardAgain = registry.capture(
      OriginalFrameEntry(key: Self.w2, frame: Self.frameA, via: .keyboard))
    #expect(!keyboardAgain)
    #expect(registry.entry(Self.w2)?.frame == Self.frameB)

    // recordSnap stores the last applied frame and leaves the entry alone.
    let record = LastSnapRecord(
      key: Self.w1, display: Self.display, zones: [1], frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    registry.recordSnap(record)
    #expect(registry.lastSnap(Self.w1) == record)
    #expect(registry.entry(Self.w1) == mouse)
    #expect(registry.lastSnap(Self.w2) == nil)

    // Unknown windows have nothing.
    #expect(registry.entry(WindowKey(pid: 5, elementHash: 5)) == nil)
  }
}
