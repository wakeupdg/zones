import CoreGraphics
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

/// A live Span across a topology change mid-drag (T67, CHANGELOG 0.1.0 known issue from the T39 review).
@Suite struct SpanTopologyTests {
  typealias F = DragFixtures

  static let held: ModifierSet = [.shift, .control]

  /// Display A of the drag fixture with a two-column Layout in place of the nine-Zone Grid.
  static func twoColumnContext() -> ArmContext {
    var twoColumns = Fixtures.nineZone
    twoColumns.id = LayoutID(rawValue: "test:two-columns")
    twoColumns.root = .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf)
    var ctx = F.context(displays: [0, 1])
    ctx.layouts[F.primaryKey] = LayoutMath.resolve(twoColumns, display: F.topology.displays[0])
    return ctx
  }

  /// Armed with both modifiers held on the nine-Zone Grid of Display A, swept over Zones 5 and 6.
  static func sweptFiveAndSix() -> DragState {
    let armContext = F.context(displays: [0, 1])
    let armed = DragSessionReducerTests.armedAt(F.center(5), context: armContext, flags: held)
    return DragSessionReducer.reduce(armed, .dragged(point: F.center(6), flags: held)).0
  }

  @Test func spanNumbersFromOldLayoutNeverReachTheDrop() throws {
    let swept = Self.sweptFiveAndSix()
    guard case .armed(_, _, _, _, _, _, _, let before, _, _) = swept else {
      Issue.record("not armed: \(swept)")
      return
    }
    #expect(before.zones == [5, 6])

    // The snapshot changes under the live Span: Display A now has two columns, so Zones 5 and 6 do not exist.
    let newCtx = Self.twoColumnContext()
    let (next, _) = DragSessionReducer.reduce(swept, .topologyChanged(newCtx))
    let numbers = Set(newCtx.layouts[F.primaryKey]!.zones.map(\.number))
    guard case .armed(_, _, _, _, _, _, _, let span, _, _) = next else {
      Issue.record("not armed after topologyChanged: \(next)")
      return
    }
    #expect(span.zones.isSubset(of: numbers), "stored Span \(span.zones) names Zones absent from \(numbers)")

    let (_, up) = DragSessionReducer.reduce(next, .mouseUp(point: F.center(6), flags: Self.held))
    guard case .snap(let plan)? = up.last else {
      Issue.record("no snap: \(up)")
      return
    }
    #expect(plan.zones.isSubset(of: numbers), "drop names Zones \(plan.zones) absent from \(numbers)")
    #expect(plan.target == Span.rect(plan.zones, in: newCtx.layouts[F.primaryKey]!))
  }
}
