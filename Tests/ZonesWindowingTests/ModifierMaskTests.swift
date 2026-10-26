import Testing
import ZonesCore
import ZonesTestSupport

@Suite struct ModifierMaskTests {
  private static let shiftBit: UInt64 = 1 << 17
  private static let controlBit: UInt64 = 1 << 18
  private static let optionBit: UInt64 = 1 << 19
  private static let commandBit: UInt64 = 1 << 20
  private static let capsLockBit: UInt64 = 1 << 16
  private static let keypadBit: UInt64 = 1 << 21
  private static let fnBit: UInt64 = 1 << 23
  private static let fourBits = shiftBit | controlBit | optionBit | commandBit

  @Test func ignoresNonModifierBits() {
    let noisy = Self.shiftBit | Self.capsLockBit | Self.fnBit | Self.keypadBit
    #expect(ModifierSet.masked(noisy) == .shift)
    #expect(ModifierSet.masked(noisy).contains(ModifierSet(.shift)))
    #expect(ModifierSet.masked(Self.capsLockBit).isEmpty)
    #expect(ModifierSet.masked(0).isEmpty)

    #expect(ModifierSet.masked(Self.shiftBit) == .shift)
    #expect(ModifierSet.masked(Self.controlBit) == .control)
    #expect(ModifierSet.masked(Self.optionBit) == .option)
    #expect(ModifierSet.masked(Self.commandBit) == .command)

    var g = Generator(seed: 51)
    for _ in 0..<500 {
      let x = g.next()
      let m = ModifierSet.masked(x)
      #expect(m == ModifierSet.masked(x & Self.fourBits), "x=\(x)")
      #expect(m.contains(.shift) == (x & Self.shiftBit != 0), "x=\(x)")
      #expect(m.contains(.control) == (x & Self.controlBit != 0), "x=\(x)")
      #expect(m.contains(.option) == (x & Self.optionBit != 0), "x=\(x)")
      #expect(m.contains(.command) == (x & Self.commandBit != 0), "x=\(x)")
    }
  }

  @Test(arguments: Modifier.allCases)
  func initFromModifierMapsToOwnSet(_ m: Modifier) {
    let expected: ModifierSet =
      switch m {
      case .shift: .shift
      case .control: .control
      case .option: .option
      case .command: .command
      }
    #expect(ModifierSet(m) == expected)
  }
}
