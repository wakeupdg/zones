import CoreGraphics
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

@Suite struct OverlayModelTests {
  static let topology = Fixtures.threeDisplays

  static func appearance(_ opacity: Double, fill: RGBA = RGBA(r: 0.2, g: 0.4, b: 0.9, a: 1)) -> Appearance {
    Appearance(fill: fill, opacity: opacity, defaultInsets: Insets(margin: 0, gap: 0))
  }

  static func scene(
    opacity: Double = 0.5, fill: RGBA = RGBA(r: 0.2, g: 0.4, b: 0.9, a: 1), reduceTransparency: Bool = false,
    reduceMotion: Bool = false
  ) -> OverlayScene {
    let dict = Fixtures.layouts(topology, Fixtures.nineZone)
    return OverlayScene(
      layouts: topology.displays.compactMap { dict[$0.key] }, appearance: appearance(opacity, fill: fill),
      options: AccessibilityOptions(reduceTransparency: reduceTransparency, reduceMotion: reduceMotion))
  }

  static func inside(_ inner: CGRect, _ outer: CGRect) -> Bool {
    let e = 1e-6
    return inner.minX >= outer.minX - e && inner.minY >= outer.minY - e && inner.maxX <= outer.maxX + e
      && inner.maxY <= outer.maxY + e
  }

  @Test func zonesWithinVisibleFrame() throws {
    let panels = OverlayModel.panels(Self.scene(), topology: Self.topology)
    #expect(panels.count == 3)
    #expect(panels.map(\.display) == Self.topology.displays.map(\.key))
    for (panel, display) in zip(panels, Self.topology.displays) {
      #expect(panel.frame == display.frame)
      #expect(panel.zones.map(\.number) == Array(1...9))
      for z in panel.zones { #expect(Self.inside(z.rect, display.visibleFrame), "zone \(z.number) on \(display.name)") }
    }
    #expect(Self.topology.displays.contains { $0.visibleFrame != $0.frame })
    let primary = try #require(Self.topology.displays.first { $0.visibleFrame != $0.frame })
    #expect(primary.frame.height > primary.visibleFrame.height)
    let fallback = OverlayModel.panels(Self.scene())
    #expect(fallback.count == 3)
    for (panel, display) in zip(fallback, Self.topology.displays) { #expect(panel.frame == display.visibleFrame) }
  }

  @Test func highlightDistinctAtLowOpacity() {
    for o in [0.10, 0.50, 1.0] {
      let panels = OverlayModel.panels(Self.scene(opacity: o), topology: Self.topology)
      for panel in panels {
        let s = panel.style
        #expect(abs(s.idle.a - o) < 1e-9)
        for z in panel.zones { #expect(z.fill == s.idle) }
        if o == 0.10 {
          #expect(s.highlight.a - s.idle.a >= 0.25)
          #expect(s.highlight.r != s.idle.r || s.highlight.g != s.idle.g || s.highlight.b != s.idle.b)
        }
        if s.highlight.a == 1 && o == 1 {
          #expect(s.secondary.a <= s.highlight.a && s.secondary.a >= s.idle.a)
        } else {
          #expect(s.secondary.a > s.idle.a && s.secondary.a < s.highlight.a)
        }
        #expect(s.dim.a < s.idle.a)
      }
    }
  }
}
