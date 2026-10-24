import CoreGraphics
import Foundation
import ZonesCore

/// ADR-0016: a seeded, shrink-free generator (splitmix64). The same seed always yields the same sequence.
public struct Generator: Sendable {
  private var state: UInt64

  public init(seed: UInt64) { state = seed }

  public mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  public mutating func int(_ r: ClosedRange<Int>) -> Int {
    let span = UInt64(bitPattern: Int64(r.upperBound &- r.lowerBound)) &+ 1
    if span == 0 { return Int(truncatingIfNeeded: next()) }  // the full Int range
    return r.lowerBound &+ Int(truncatingIfNeeded: next() % span)
  }

  public mutating func double(_ r: ClosedRange<Double>) -> Double {
    let unit = Double(next() >> 11) / Double(1 << 53)  // [0, 1)
    return min(r.lowerBound + unit * (r.upperBound - r.lowerBound), r.upperBound)
  }

  public mutating func bool() -> Bool { next() & 1 == 1 }

  public mutating func pick<T>(_ xs: [T]) -> T {
    precondition(!xs.isEmpty, "pick from an empty array")
    return xs[int(0...(xs.count - 1))]
  }

  /// A random split tree no deeper than `maxDepth`; every ratio lies in `minFraction...(1 - minFraction)`.
  public mutating func tree(maxDepth: Int, minFraction: Double = Constants.minFraction) -> SplitNode {
    guard maxDepth > 0, int(0...9) < 7 else { return .leaf }
    return .split(
      axis: bool() ? .horizontal : .vertical,
      ratio: double(minFraction...(1 - minFraction)),
      first: tree(maxDepth: maxDepth - 1, minFraction: minFraction),
      second: tree(maxDepth: maxDepth - 1, minFraction: minFraction))
  }

  public mutating func layout(maxDepth: Int) -> Layout {
    let id = UUID(uuid: Self.uuidBytes(high: next(), low: next()))
    let root = tree(maxDepth: maxDepth)
    return Layout(
      id: LayoutID(rawValue: id.uuidString), name: "Generated \(int(0...9999))", root: root,
      surround: Surround(top: 0, left: 0, bottom: 0, right: 0), insets: Insets(margin: 0, gap: 0))
  }

  /// A rectangle with positive size lying inside `bounds`.
  public mutating func rect(in bounds: CGRect) -> CGRect {
    let width = double(min(1, bounds.width)...bounds.width)
    let height = double(min(1, bounds.height)...bounds.height)
    let x = double(bounds.minX...(bounds.maxX - width))
    let y = double(bounds.minY...(bounds.maxY - height))
    return CGRect(x: x, y: y, width: width, height: height)
  }

  /// Contains `seed=<int>` and a compact description of the layout, so a failure replays from the message.
  public static func failureMessage(seed: UInt64, layout: Layout, note: String) -> String {
    "seed=\(seed) layout=\(layout.name) id=\(layout.id.rawValue) root=\(describe(layout.root)) \(note)"
  }

  private static func describe(_ node: SplitNode) -> String {
    switch node {
    case .leaf: "L"
    case .split(let axis, let ratio, let first, let second):
      "\(axis == .horizontal ? "H" : "V")(\(ratio),\(describe(first)),\(describe(second)))"
    }
  }

  private static func uuidBytes(high: UInt64, low: UInt64) -> uuid_t {
    var bytes: [UInt8] = []
    for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: high >> UInt64(shift))) }
    for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: low >> UInt64(shift))) }
    return (
      bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
      bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    )
  }
}
