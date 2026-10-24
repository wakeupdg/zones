import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport

@testable import ZonesWindowing

@Suite(.serialized) struct ShortcutResolverTests {
  typealias F = ShortcutFixtures

  static let columns2 = Templates.builtInID(.columns, count: 2)
  static let grid4 = Templates.builtInID(.grid, count: 4)

  /// AC-098: the target Display is the one the window overlaps most, and the Zones are its own Assignment's.
  @Test func sendToZoneUsesOccupiedDisplay() throws {
    let layouts = F.layouts(a: Self.columns2, b: Self.grid4)
    let layoutA = try #require(layouts[F.displayA]), layoutB = try #require(layouts[F.displayB])
    #expect(layoutA.zones.count == 2 && layoutB.zones.count == 4)

    // Mostly on B, with a sliver on A.
    let onB = F.focused(frame: CGRect(x: 1900, y: 200, width: 600, height: 400))
    for mode in [SnapMode.full, .positionOnly] {
      let plan = ShortcutResolver.plan(
        .sendToZone(3), focused: onB, verdict: .allow(mode), topology: F.topology, layouts: layouts,
        registry: OriginalFrameRegistry())
      guard case .snap(let snap) = plan else {
        Issue.record("expected a snap plan, got \(plan)")
        continue
      }
      #expect(snap.display == F.displayB)
      #expect(snap.zones == [3])
      #expect(snap.target == layoutB.zones[2].frame)
      #expect(snap.via == .keyboard)
      #expect(snap.originalFrame == onB.frame)
      #expect(snap.mode == mode)
      #expect(snap.window == onB.record.ref)
    }

    // The same window moved onto A: A's Zone 2 (Zone 3 does not exist on a 2-Zone Layout).
    let onA = F.focused(frame: CGRect(x: 100, y: 200, width: 600, height: 400))
    let planA = ShortcutResolver.plan(
      .sendToZone(2), focused: onA, verdict: .allow(.full), topology: F.topology, layouts: layouts,
      registry: OriginalFrameRegistry())
    guard case .snap(let snapA) = planA else {
      Issue.record("expected a snap plan, got \(planA)")
      return
    }
    #expect(snapA.display == F.displayA)
    #expect(snapA.zones == [2])
    #expect(snapA.target == layoutA.zones[1].frame)
  }
}
