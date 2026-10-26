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
  static let sampleCount = 9
  static let frameBudget: Duration = .microseconds(8333)

  static let keyA = DisplayKey.uuid("00000000-0000-0000-0000-0000000000A1")
  static let keyB = DisplayKey.uuid("00000000-0000-0000-0000-0000000000A2")
  static let keyC = DisplayKey.uuid("00000000-0000-0000-0000-0000000000A3")

  /// Three Displays like the QA rig: 3008x1692, 3008x1692 and 1800x1169 points at scale 2. `extra` grows every Display
  /// so each sample gets sizes no earlier sample used (fresh backing stores and glyph sizes, never a warm repeat).
  static func topology(growingBy extra: Double = 0) -> TopologySnapshot {
    let a = CGRect(x: 0, y: 0, width: 3008 + extra, height: 1692)
    let b = CGRect(x: -3008 - extra, y: -162, width: 3008 + extra, height: 1692 + extra)
    let c = CGRect(x: -4808 - extra, y: 90, width: 1800 + extra, height: 1169)
    let displays = [(keyA, a), (keyB, b), (keyC, c)].map { key, frame in
      DisplaySnapshot(
        key: key, frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 24), scale: 2, isMain: key == keyA,
        mirrorOf: nil, name: "test", resolution: frame.size)
    }
    return TopologySnapshot(displays: displays, separateSpaces: true, primaryFrame: a)
  }

  /// The AC-040 budget: one fresh presenter per sample, resized the way launch does, then the first show + flush of a
  /// 9-Zone scene. Every sample has Display sizes no earlier sample used, so none reuses a backing store or glyph size,
  /// and each presenter's panels are released afterwards so hidden Display-sized windows do not pile up and slow the
  /// next sample. The best sample must fit one 120 Hz frame; a loaded Mac adds scheduling noise to any single
  /// sample, which is why this guards the budget and `panelsWarmedAtResizeWhileOrderedOut` is what tells fixed code
  /// from unfixed code (wall time alone cannot: medians measured 7.5 to 8.8 ms with the warm-up and 12 to 13 ms without).
  @Test func firstShowUnderOneFrame() {
    let clock = ContinuousClock()
    var samples: [Duration] = []
    for index in 0..<Self.sampleCount {
      let topology = Self.topology(growingBy: Double(index) * 37)
      let scene = OverlayPanelTests.scene(topology.displays, zonesPerDisplay: Self.nineZones)
      let presenter = PanelOverlayPresenter(topology: { topology })
      presenter.resize(to: topology)
      let start = clock.now
      presenter.show(scene)
      CATransaction.flush()
      samples.append(clock.now - start)
      presenter.hide()
      presenter.resize(to: TopologySnapshot(displays: [], separateSpaces: true, primaryFrame: .zero))
    }
    let best = samples.min() ?? .seconds(1)
    #expect(best < Self.frameBudget, "best first show+flush took \(best); samples \(samples.sorted())")
  }

  @Test func layersBuiltAtResize() {
    let topology = Self.topology()
    let presenter = PanelOverlayPresenter(topology: { topology })
    presenter.resize(to: topology)
    for display in topology.displays {
      let view = presenter.layerView(for: display.key)
      #expect(view?.zoneNumbers == Array(1...Self.nineZones))
      #expect(view?.layer?.sublayers?.count == Self.nineZones * 2 + 2)
      #expect(view?.labelLayer(1)?.frame.isEmpty == false, "labels are laid out so the warm-up commit rasterizes text")
      #expect(presenter.panel(for: display.key)?.isVisible == false)
    }
  }

  /// The first show must not pay for the first window-server commit of a Display-sized panel, so `resize` commits
  /// each panel once while it is transparent and ordered out, and again only when its size changes.
  @Test func panelsWarmedAtResizeWhileOrderedOut() {
    let topology = Self.topology()
    let presenter = PanelOverlayPresenter(topology: { topology })
    presenter.resize(to: topology)
    for display in topology.displays {
      let panel = presenter.panel(for: display.key)
      #expect(panel?.warmUpCount == 1)
      #expect(panel?.orderFrontCount == 0)
      #expect(panel?.isVisible == false)
      #expect(panel?.alphaValue == 1)
    }
    presenter.resize(to: topology)
    #expect(topology.displays.allSatisfy { presenter.panel(for: $0.key)?.warmUpCount == 1 }, "same size: no second warm-up")
    let grown = Self.topology(growingBy: 40)
    presenter.resize(to: grown)
    #expect(grown.displays.allSatisfy { presenter.panel(for: $0.key)?.warmUpCount == 2 }, "new size: warmed again")
    presenter.show(OverlayPanelTests.scene(grown.displays, zonesPerDisplay: Self.nineZones))
    #expect(grown.displays.allSatisfy { presenter.panel(for: $0.key)?.orderFrontCount == 1 })
  }
}
