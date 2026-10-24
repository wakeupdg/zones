import CoreGraphics
import Foundation
import ZonesCore
import ZonesLayout

/// One Zone as the panel draws it. `rect` is in AppKit global coordinates (the panel view converts it).
public struct ZoneDrawing: Hashable, Sendable {
  public var number: Int
  public var rect: CGRect
  public var fill: RGBA
  public var label: ZoneLabel
  public init(number: Int, rect: CGRect, fill: RGBA, label: ZoneLabel) {
    self.number = number
    self.rect = rect
    self.fill = fill
    self.label = label
  }
}

public struct PanelStyle: Hashable, Sendable {
  public var idle: RGBA
  public var highlight: RGBA
  public var secondary: RGBA
  public var dim: RGBA
  public var animationDuration: Double?
  public init(idle: RGBA, highlight: RGBA, secondary: RGBA, dim: RGBA, animationDuration: Double?) {
    self.idle = idle
    self.highlight = highlight
    self.secondary = secondary
    self.dim = dim
    self.animationDuration = animationDuration
  }
}

public struct PanelModel: Hashable, Sendable {
  public var display: DisplayKey
  public var frame: CGRect
  public var zones: [ZoneDrawing]
  public var style: PanelStyle
  public var spanOutline: Bool
  public init(display: DisplayKey, frame: CGRect, zones: [ZoneDrawing], style: PanelStyle, spanOutline: Bool) {
    self.display = display
    self.frame = frame
    self.zones = zones
    self.style = style
    self.spanOutline = spanOutline
  }
}

public enum OverlayModel {
  public static let animationSeconds = 0.12

  /// Contract signature. Without a topology the panel frame falls back to the layout's visible frame; the presenter
  /// must call `panels(_:topology:)` so the panel covers the full Display frame.
  public static func panels(_ s: OverlayScene) -> [PanelModel] {
    build(s) { $0.visibleFrame }
  }

  /// Panel frame = the full Display frame from `topology` (visible frame when the Display is absent).
  public static func panels(_ s: OverlayScene, topology: TopologySnapshot) -> [PanelModel] {
    let frames = Dictionary(topology.displays.map { ($0.key, $0.frame) }, uniquingKeysWith: { a, _ in a })
    return build(s) { frames[$0.display] ?? $0.visibleFrame }
  }

  /// Repaints every Zone from `style`: dim everywhere when `dimAll`; else the panel for `h.display` paints primary,
  /// then secondary, then idle, and every other panel is all idle. Geometry, labels, style and `spanOutline` are
  /// untouched, so the result is a pure function of the arguments.
  public static func apply(_ h: Highlight, to panels: [PanelModel]) -> [PanelModel] {
    panels.map { panel in
      var out = panel
      let style = panel.style
      let active = !h.dimAll && h.display == panel.display
      out.zones = panel.zones.map { zone in
        var z = zone
        if h.dimAll {
          z.fill = style.dim
        } else if active, h.primary.contains(zone.number) {
          z.fill = style.highlight
        } else if active, h.secondary.contains(zone.number) {
          z.fill = style.secondary
        } else {
          z.fill = style.idle
        }
        return z
      }
      return out
    }
  }

  private static func build(_ s: OverlayScene, frame: (ResolvedLayout) -> CGRect) -> [PanelModel] {
    let style = makeStyle(s.appearance, s.options)
    return s.layouts.map { layout in
      let labels = Dictionary(
        LabelModel.labels(layout, appearance: s.appearance).map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })
      let zones = layout.zones.sorted { $0.number < $1.number }.compactMap { zone -> ZoneDrawing? in
        guard let label = labels[zone.number] else { return nil }
        return ZoneDrawing(number: zone.number, rect: zone.frame, fill: style.idle, label: label)
      }
      return PanelModel(
        display: layout.display, frame: frame(layout), zones: zones, style: style, spanOutline: false)
    }
  }

  // MARK: colors

  private static func makeStyle(_ appearance: Appearance, _ options: AccessibilityOptions) -> PanelStyle {
    let f = appearance.fill
    let o = min(max(appearance.opacity, 0), 1)
    let ext = luminance(f) < 0.5 ? RGBA(r: 1, g: 1, b: 1, a: 1) : RGBA(r: 0, g: 0, b: 0, a: 1)
    let lifted = mix(f, ext, 0.35)
    let idle = rgba(f, a: o)
    let highlight = rgba(lifted, a: min(1, max(o + 0.30, 0.40)))
    return PanelStyle(
      idle: idle, highlight: highlight, secondary: rgba(lifted, a: (idle.a + highlight.a) / 2),
      dim: rgba(f, a: o * 0.4), animationDuration: nil)
  }

  private static func rgba(_ c: RGBA, a: Double) -> RGBA { RGBA(r: c.r, g: c.g, b: c.b, a: a) }

  private static func mix(_ c: RGBA, _ t: RGBA, _ k: Double) -> RGBA {
    RGBA(r: c.r + (t.r - c.r) * k, g: c.g + (t.g - c.g) * k, b: c.b + (t.b - c.b) * k, a: 1)
  }

  /// WCAG 2 relative luminance (sRGB linearization), alpha ignored.
  private static func luminance(_ c: RGBA) -> Double {
    func lin(_ v: Double) -> Double {
      let x = min(max(v, 0), 1)
      return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
  }
}
