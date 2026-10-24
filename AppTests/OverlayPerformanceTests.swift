import AppKit
import Testing
import ZonesCore
import ZonesWindowing

@testable import Zones

/// AC-040: the first Shift-drag arm after launch must fit one 120 Hz frame, so the overlay panels build their layers
/// while they are still ordered out.
@MainActor
@Suite struct OverlayPerformanceTests {
  static let nineZones = 9
  static let frameBudget: Duration = .microseconds(8333)

  static let keyA = DisplayKey.uuid("00000000-0000-0000-0000-0000000000A1")
  static let keyB = DisplayKey.uuid("00000000-0000-0000-0000-0000000000A2")
  static let keyC = DisplayKey.uuid("00000000-0000-0000-0000-0000000000A3")

  /// Three Displays like the QA rig: 3008x1692, 3008x1692 and 1800x1169 points at scale 2.
  static var topology: TopologySnapshot {
    let a = CGRect(x: 0, y: 0, width: 3008, height: 1692)
    let b = CGRect(x: -3008, y: -162, width: 3008, height: 1692)
    let c = CGRect(x: -4808, y: 90, width: 1800, height: 1169)
    let displays = [(keyA, a), (keyB, b), (keyC, c)].map { key, frame in
      DisplaySnapshot(
        key: key, frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 24), scale: 2, isMain: key == keyA,
        mirrorOf: nil, name: "test", resolution: frame.size)
    }
    return TopologySnapshot(displays: displays, separateSpaces: true, primaryFrame: a)
  }

  @Test func firstShowUnderOneFrame() {
    let topology = Self.topology
    let scene = OverlayPanelTests.scene(topology.displays, zonesPerDisplay: Self.nineZones)
    let clock = ContinuousClock()
    var best: Duration = .seconds(1)
    for _ in 0..<3 {
      let presenter = PanelOverlayPresenter(topology: { topology })
      presenter.resize(to: topology)
      let start = clock.now
      presenter.show(scene)
      CATransaction.flush()
      best = min(best, clock.now - start)
      presenter.hide()
    }
    #expect(best < Self.frameBudget, "first show+flush took \(best)")
  }

  @Test func layersBuiltAtResize() {
    let topology = Self.topology
    let presenter = PanelOverlayPresenter(topology: { topology })
    presenter.resize(to: topology)
    for display in topology.displays {
      let view = presenter.layerView(for: display.key)
      #expect(view?.zoneNumbers == Array(1...Self.nineZones))
      #expect(view?.layer?.sublayers?.count == Self.nineZones * 2 + 2)
      #expect(presenter.panel(for: display.key)?.isVisible == false)
    }
  }
}
