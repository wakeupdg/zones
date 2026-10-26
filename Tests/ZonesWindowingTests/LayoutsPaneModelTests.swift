import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

@Suite struct LayoutsPaneModelTests {
  /// AC-120
  @Test func rows() throws {
    let three = Fixtures.threeDisplays
    var unstable = three.displays[2]
    unstable.key = .unstable("dup:XYZ#9")
    unstable.name = "Twin"
    let topology = TopologySnapshot(
      displays: [three.displays[0], three.displays[1], unstable], separateSpaces: true,
      primaryFrame: three.primaryFrame)

    let absentB = Assignment(
      layout: LayoutID(rawValue: "builtin:columns:2"), displayName: "Studio", lastVisibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
      lastScale: 2, lastSeen: nil)
    let absentA = Assignment(
      layout: LayoutID(rawValue: "builtin:focus:1"), displayName: "Abacus", lastVisibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
      lastScale: 1, lastSeen: nil)
    let primaryRecord = Assignment(
      layout: LayoutID(rawValue: "builtin:grid:4"), displayName: "Primary 1x", lastVisibleFrame: three.displays[0].visibleFrame,
      lastScale: 1, lastSeen: nil)
    let assignments = [
      "99999999-9999-4999-8999-999999999999": absentB,
      "88888888-8888-4888-8888-888888888888": absentA,
      "11111111-1111-4111-8111-111111111111": primaryRecord,
    ]
    let session: [DisplayKey: LayoutID] = [.unstable("dup:XYZ#9"): LayoutID(rawValue: "builtin:focus:1")]

    let rows = LayoutsPaneModel.rows(topology, assignments: assignments, session: session)
    #expect(rows.count == 5)

    #expect(rows[0] == .attached(three.displays[0], LayoutID(rawValue: "builtin:grid:4"), unstable: false))
    #expect(rows[1] == .attached(three.displays[1], Templates.builtInID(.priorityGrid, count: 3), unstable: false))
    #expect(rows[2] == .attached(unstable, LayoutID(rawValue: "builtin:focus:1"), unstable: true))
    if case .attached(let display, _, let flagged) = rows[2] {
      #expect(flagged)
      #expect(display.resolution == three.displays[2].resolution)
    }
    #expect(LayoutsPaneModel.notSavedLabel == "not saved")

    // Disconnected rows: sorted by name, then key; copy targets are attached UUID keys only.
    let targets: [DisplayKey] = [three.displays[0].key, three.displays[1].key]
    #expect(rows[3] == .disconnected(key: "88888888-8888-4888-8888-888888888888", absentA, copyTargets: targets))
    #expect(rows[4] == .disconnected(key: "99999999-9999-4999-8999-999999999999", absentB, copyTargets: targets))
    #expect(LayoutsPaneModel.copyTitle(three.displays[1]) == "Copy Assignment to Left 2x")
    #expect(LayoutsPaneModel.forgetTitle == "Forget")
  }
}
