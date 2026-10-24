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

  @Test func applyPaintsPrimarySecondaryDim() {
    let base = OverlayModel.panels(Self.scene(opacity: 0.5), topology: Self.topology)
    let keys = Self.topology.displays.map(\.key)
    let h = Highlight(display: keys[0], primary: [3], secondary: [5, 7], dimAll: false)
    let out = OverlayModel.apply(h, to: base)
    let s = base[0].style
    for z in out[0].zones {
      switch z.number {
      case 3: #expect(z.fill == s.highlight)
      case 5, 7: #expect(z.fill == s.secondary)
      default: #expect(z.fill == s.idle)
      }
    }
    for i in 1...2 { for z in out[i].zones { #expect(z.fill == out[i].style.idle) } }

    let both = OverlayModel.apply(
      Highlight(display: keys[0], primary: [4], secondary: [4], dimAll: false), to: base)
    #expect(both[0].zones.first { $0.number == 4 }?.fill == s.highlight)

    let dim = OverlayModel.apply(Highlight(display: keys[1], primary: [1], secondary: [], dimAll: true), to: base)
    for p in dim { for z in p.zones { #expect(z.fill == p.style.dim) } }

    let none = OverlayModel.apply(Highlight(display: nil, primary: [], secondary: [], dimAll: false), to: base)
    #expect(none == base)
    let nilDisplay = OverlayModel.apply(Highlight(display: nil, primary: [1], secondary: [2], dimAll: false), to: base)
    #expect(nilDisplay == base)

    for p in [out, dim] {
      for (a, b) in zip(p, base) {
        #expect(a.frame == b.frame && a.style == b.style && a.spanOutline == b.spanOutline)
        #expect(a.zones.map(\.rect) == b.zones.map(\.rect) && a.zones.map(\.label) == b.zones.map(\.label))
        #expect(a.zones.map(\.number) == b.zones.map(\.number))
      }
    }
    #expect(OverlayModel.apply(h, to: out) == out)
    #expect(OverlayModel.apply(Highlight(display: nil, primary: [], secondary: [], dimAll: false), to: out) == base)
  }

  /// WCAG 2 contrast ratio, written independently of LabelModel.
  static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
    func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    func lum(_ c: RGBA) -> Double { 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b) }
    let (hi, lo) = (max(lum(a), lum(b)), min(lum(a), lum(b)))
    return (hi + 0.05) / (lo + 0.05)
  }

  @Test func labelsLegibleAndScaled() {
    let fills = [RGBA(r: 0.2, g: 0.4, b: 0.9, a: 1), RGBA(r: 0.46, g: 0.46, b: 0.46, a: 1)]
    for fill in fills {
      for o in [0.1, 0.5, 1.0] {
        let panels = OverlayModel.panels(Self.scene(opacity: o, fill: fill), topology: Self.topology)
        for (panel, display) in zip(panels, Self.topology.displays) {
          for z in panel.zones {
            #expect(z.label.text == String(z.number))
            #expect(z.label.number == z.number)
            #expect(z.label.contentsScale == display.scale)
            let opaque = RGBA(r: fill.r, g: fill.g, b: fill.b, a: 1)
            #expect(Self.contrast(z.label.outline, opaque) >= 4.5, "fill \(fill) opacity \(o)")
          }
        }
        #expect(panels[1].zones.allSatisfy { $0.label.contentsScale == 2 })
        #expect(panels[0].zones.allSatisfy { $0.label.contentsScale == 1 })
      }
    }
  }

  @Test func accessibilityOptions() {
    let o = 0.10
    let def = OverlayModel.panels(Self.scene(opacity: o), topology: Self.topology)
    for p in def {
      #expect(!p.spanOutline)
      #expect(p.style.animationDuration == OverlayModel.animationSeconds)
      #expect(abs(p.style.idle.a - o) < 1e-9)
    }
    let motion = OverlayModel.panels(Self.scene(opacity: o, reduceMotion: true), topology: Self.topology)
    for (m, d) in zip(motion, def) {
      #expect(m.style.animationDuration == nil)
      var restyled = m
      restyled.style.animationDuration = OverlayModel.animationSeconds
      #expect(restyled == d)
    }
    for reduceMotion in [false, true] {
      let solid = OverlayModel.panels(
        Self.scene(opacity: o, reduceTransparency: true, reduceMotion: reduceMotion), topology: Self.topology)
      let h = Highlight(display: solid[0].display, primary: [1], secondary: [2], dimAll: false)
      for p in solid + OverlayModel.apply(h, to: solid) {
        #expect(p.style.idle.a == 1 && p.style.highlight.a == 1 && p.style.dim.a == 1)
        #expect(p.style.secondary.a == 0)
        #expect(p.spanOutline)
        #expect(
          p.style.highlight.r != p.style.idle.r || p.style.highlight.g != p.style.idle.g
            || p.style.highlight.b != p.style.idle.b)
        #expect((p.style.animationDuration == nil) == reduceMotion)
      }
    }
  }
}
