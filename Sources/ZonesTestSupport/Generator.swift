import CoreGraphics
import Foundation
import ZonesCore
import ZonesWindowing

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

  /// A random split tree no deeper than `maxDepth`. Every leaf is at least `minFraction` of the unit square on each
  /// axis (a split is only offered on an axis whose remaining extent can host two such leaves), so every ratio lies in
  /// `minFraction...(1 - minFraction)` and the tree is valid however deep it grows.
  public mutating func tree(maxDepth: Int, minFraction: Double = Constants.minFraction) -> SplitNode {
    tree(maxDepth: maxDepth, minFraction: minFraction, width: 1, height: 1)
  }

  private mutating func tree(maxDepth: Int, minFraction: Double, width: Double, height: Double) -> SplitNode {
    guard maxDepth > 0, int(0...9) < 7 else { return .leaf }
    var axes: [SplitAxis] = []
    if width >= 2 * minFraction { axes.append(.horizontal) }
    if height >= 2 * minFraction { axes.append(.vertical) }
    guard !axes.isEmpty else { return .leaf }
    let axis = pick(axes)
    let extent = axis == .horizontal ? width : height
    let ratio = double((minFraction / extent)...(1 - minFraction / extent))
    let (w1, h1, w2, h2) =
      axis == .horizontal
      ? (width * ratio, height, width - width * ratio, height)
      : (width, height * ratio, width, height - height * ratio)
    return .split(
      axis: axis, ratio: ratio,
      first: tree(maxDepth: maxDepth - 1, minFraction: minFraction, width: w1, height: h1),
      second: tree(maxDepth: maxDepth - 1, minFraction: minFraction, width: w2, height: h2))
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

  /// Exactly `count` reproducible `DragEvent`s for one window (id 1, frame `Fixtures.dragDownFrame`). The first is a
  /// `mouseDown`; the rest mix every event kind. The generator tracks the modifier set it last produced, so
  /// `dragged`, `mouseDown` and most `mouseUp` events carry the flags currently held. Points fall mostly inside a
  /// Display's visible frame, sometimes in the surround or beyond every Display. A `topologyChanged` or `armContext`
  /// carries `context` or a variant of it (fewer Displays, Original Frame flipped).
  public mutating func dragEvents(count: Int, context: ArmContext, config: ModifierConfig) -> [DragEvent] {
    guard count > 0 else { return [] }
    let window = WindowRef(
      id: WindowID(rawValue: 1), pid: 100, bundleID: "test.app1", frame: Fixtures.dragDownFrame, layer: 0)
    var held: ModifierSet = []
    var events: [DragEvent] = []
    events.reserveCapacity(count)

    func randomFlags(_ g: inout Generator) -> ModifierSet {
      var set: ModifierSet = []
      if g.int(0...9) < 7 { set.formUnion(ModifierSet(config.activation)) }
      if g.int(0...9) < 5 { set.formUnion(ModifierSet(config.span)) }
      if g.int(0...19) == 0 { set.formUnion(.option) }  // an unrelated modifier
      return set
    }

    held = randomFlags(&self)
    events.append(
      .mouseDown(
        point: Fixtures.dragDownPoint, flags: held, candidates: [window], phaseOne: .allow(.full), config: config))

    while events.count < count {
      let roll = int(0...99)
      switch roll {
      case 0..<8:
        held = randomFlags(&self)
        events.append(
          .mouseDown(
            point: Fixtures.dragDownPoint, flags: held, candidates: [window], phaseOne: .allow(.full),
            config: config))
      case 8..<48:
        events.append(.dragged(point: dragPoint(in: context), flags: held))
      case 48..<62:
        held = randomFlags(&self)
        events.append(.flagsChanged(held))
      case 62..<76:
        events.append(.frameSample([window.id: sampleResult(down: Fixtures.dragDownFrame)]))
      case 76..<80:
        events.append(.armContext(variant(of: context)))
      case 80..<87:
        events.append(.mouseUp(point: dragPoint(in: context), flags: int(0...9) < 8 ? held : randomFlags(&self)))
      case 87..<90:
        events.append(.windowGone)
      case 90..<94:
        events.append(.topologyChanged(variant(of: context)))
      case 94..<97:
        events.append(.spaceChanged)
      default:
        events.append(.wake)
      }
    }
    return events
  }

  private mutating func dragPoint(in context: ArmContext) -> CGPoint {
    let displays = context.topology.displays
    guard !displays.isEmpty, int(0...9) < 9 else {
      return CGPoint(x: double(4000...6000), y: double(4000...6000))  // beyond every Display
    }
    let display = pick(displays)
    let area = int(0...9) < 8 ? display.visibleFrame : display.frame
    return CGPoint(
      x: double(area.minX...(area.maxX - 0.5)), y: double(area.minY...(area.maxY - 0.5)))
  }

  private mutating func sampleResult(down: CGRect) -> SampleResult {
    switch int(0...9) {
    case 0..<5:
      return .frame(down.offsetBy(dx: double(10...80), dy: double(-40...40)), Fixtures.dragStandardFacts)
    case 5..<8: return .frame(down, Fixtures.dragStandardFacts)
    case 8: return .timedOut
    default: return .gone
    }
  }

  /// `context` itself, or a copy with one Display dropped from the arm snapshot, or the Original Frame flipped.
  private mutating func variant(of context: ArmContext) -> ArmContext {
    var ctx = context
    switch int(0...3) {
    case 0: break
    case 1:
      ctx.hasOriginalFrame.toggle()
    case 2:
      guard ctx.topology.displays.count > 1 else { break }
      let dropped = ctx.topology.displays.removeLast()
      ctx.layouts[dropped.key] = nil
    default:
      ctx.hasOriginalFrame = true
    }
    return ctx
  }

  /// Contains `seed=<int>` (plain decimal) and the layout's full description, so a failure replays from the message.
  public static func failureMessage(seed: UInt64, layout: Layout, note: String) -> String {
    "seed=\(seed) layout=\(String(describing: layout)) note=\(note)"
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
