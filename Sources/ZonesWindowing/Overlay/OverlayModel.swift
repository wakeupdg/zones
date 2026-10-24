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

  public static func apply(_ h: Highlight, to panels: [PanelModel]) -> [PanelModel] {
    panels
  }

  private static func build(_ s: OverlayScene, frame: (ResolvedLayout) -> CGRect) -> [PanelModel] {
    let style = PanelStyle(
      idle: RGBA(r: s.appearance.fill.r, g: s.appearance.fill.g, b: s.appearance.fill.b, a: s.appearance.opacity),
      highlight: s.appearance.fill, secondary: s.appearance.fill, dim: s.appearance.fill, animationDuration: nil)
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
}
