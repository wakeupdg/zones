import AppKit
import ZonesCore
import ZonesLayout
import ZonesWindowing

/// Renders one `PanelModel` with persistent `CALayer`s: a fill and a label per Zone, plus one highlight and one
/// secondary layer. No `draw(_:)`; every mutation happens inside a `CATransaction` with actions disabled.
///
/// Stacking, bottom to top: Zone fills, secondary, highlight, labels. Layers are reused for the same Zone number
/// and only touched when the value they show changed.
@MainActor
final class ZoneLayerView: NSView {
  let highlightLayer = CALayer()
  let secondaryLayer = CALayer()
  private var fillLayers: [Int: CALayer] = [:]
  private var labelLayers: [Int: CATextLayer] = [:]
  private var applied: PanelModel?
  private var highlightRect: CGRect?
  private var secondaryRect: CGRect?
  private(set) var backingScale: Double

  init(frame: CGRect, scale: Double) {
    backingScale = scale
    super.init(frame: frame)
    wantsLayer = true
    layerContentsRedrawPolicy = .never
    for (layer, z) in [(secondaryLayer, 1.0), (highlightLayer, 2.0)] {
      layer.contentsScale = scale
      layer.zPosition = z
      layer.opacity = 0
      layer.isOpaque = false
      self.layer?.addSublayer(layer)
    }
  }

  @available(*, unavailable) required init?(coder: NSCoder) { nil }

  override func isAccessibilityElement() -> Bool { false }
  override func accessibilityChildren() -> [Any]? { [] }

  var zoneNumbers: [Int] { fillLayers.keys.sorted() }
  func fillLayer(_ number: Int) -> CALayer? { fillLayers[number] }
  func labelLayer(_ number: Int) -> CATextLayer? { labelLayers[number] }

  /// Every layer this view owns, for tests.
  var allLayers: [CALayer] {
    [highlightLayer, secondaryLayer] + zoneNumbers.compactMap { fillLayers[$0] }
      + zoneNumbers.compactMap { labelLayers[$0] }
  }

  /// Builds the fill and label layers for Zones `1...count` that do not exist yet, hidden behind the panel while it is
  /// ordered out, so the first `apply` only sets frames and colors. The label text layer gets a font now, which
  /// is the slow part of its first use (AC-040).
  func prebuild(zoneCount count: Int) {
    guard count > 0 else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    for number in 1...count {
      if fillLayers[number] == nil { _ = makeFillLayer(for: number) }
      if labelLayers[number] == nil {
        let label = makeLabelLayer(for: number)
        label.contentsScale = backingScale
        label.string = NSAttributedString(
          string: String(number), attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)])
      }
    }
  }

  func apply(_ model: PanelModel, scale: Double? = nil) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }

    let scaleChanged = scale.map { $0 != backingScale } ?? false
    if let scale { backingScale = scale }
    let geometryChanged = scaleChanged || applied?.frame != model.frame
    let previous = Dictionary(
      (applied?.zones ?? []).map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })

    let live = Set(model.zones.map(\.number))
    for number in fillLayers.keys where !live.contains(number) {
      fillLayers.removeValue(forKey: number)?.removeFromSuperlayer()
      labelLayers.removeValue(forKey: number)?.removeFromSuperlayer()
    }

    for zone in model.zones {
      let before = previous[zone.number]
      let fill = fillLayers[zone.number] ?? makeFillLayer(for: zone.number)
      let label = labelLayers[zone.number] ?? makeLabelLayer(for: zone.number)
      let local = CoordinateSpace.panelLocal(zone.rect, panelFrame: model.frame)
      if geometryChanged || before?.rect != zone.rect {
        fill.frame = local
      }
      if scaleChanged { fill.contentsScale = backingScale }
      if before?.fill != zone.fill {
        fill.backgroundColor = Self.cgColor(zone.fill)
      }
      if geometryChanged || before?.label != zone.label {
        configure(label, with: zone.label, in: CoordinateSpace.panelLocal(zone.label.frame, panelFrame: model.frame))
      }
    }

    updateAccents(model, geometryChanged: geometryChanged, scaleChanged: scaleChanged)
    applied = model
  }

  // MARK: layers

  private func makeFillLayer(for number: Int) -> CALayer {
    let fill = CALayer()
    fill.contentsScale = backingScale
    fill.isOpaque = false
    fill.zPosition = 0
    layer?.addSublayer(fill)
    fillLayers[number] = fill
    return fill
  }

  private func makeLabelLayer(for number: Int) -> CATextLayer {
    let label = CATextLayer()
    label.alignmentMode = .center
    label.isWrapped = false
    label.zPosition = 3
    layer?.addSublayer(label)
    labelLayers[number] = label
    return label
  }

  private func configure(_ layer: CATextLayer, with label: ZoneLabel, in local: CGRect) {
    let size = min(max(min(local.width, local.height) * 0.3, 14), 160)
    let height = (size * 1.25).rounded(.up)
    layer.contentsScale = label.contentsScale
    layer.frame = CGRect(x: local.minX, y: local.midY - height / 2, width: local.width, height: height)
    layer.string = NSAttributedString(
      string: label.text,
      attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: .semibold),
        .foregroundColor: NSColor(cgColor: Self.cgColor(label.outline)) ?? NSColor.white,
      ])
  }

  /// The highlight layer outlines the union of the primary Zones; the secondary layer covers the union of the
  /// secondary Zones, as a border when `spanOutline` is set and as a fill otherwise. Zones are told apart by the
  /// fill the model gave them (`OverlayModel.apply`), so no Highlight value is needed here.
  private func updateAccents(_ model: PanelModel, geometryChanged: Bool, scaleChanged: Bool) {
    let style = model.style
    var primary: CGRect?
    var secondary: CGRect?
    for zone in model.zones {
      let local = CoordinateSpace.panelLocal(zone.rect, panelFrame: model.frame)
      if zone.fill == style.highlight {
        primary = primary.map { $0.union(local) } ?? local
      } else if zone.fill == style.secondary {
        secondary = secondary.map { $0.union(local) } ?? local
      }
    }
    if scaleChanged {
      highlightLayer.contentsScale = backingScale
      secondaryLayer.contentsScale = backingScale
    }

    if primary != highlightRect || geometryChanged || applied?.style != style {
      let wasVisible = highlightLayer.opacity > 0
      if let primary { highlightLayer.frame = primary }
      highlightLayer.backgroundColor = nil
      highlightLayer.borderWidth = 2
      highlightLayer.borderColor = Self.cgColor(RGBA(r: style.highlight.r, g: style.highlight.g, b: style.highlight.b, a: 1))
      highlightLayer.opacity = primary == nil ? 0 : 1
      if let duration = style.animationDuration, !wasVisible, primary != nil {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = duration
        highlightLayer.add(fade, forKey: "fade")
      }
      highlightRect = primary
    }

    if secondary != secondaryRect || geometryChanged || applied?.style != style || applied?.spanOutline != model.spanOutline {
      if let secondary { secondaryLayer.frame = secondary }
      if model.spanOutline {
        secondaryLayer.backgroundColor = nil
        secondaryLayer.borderWidth = 2
        secondaryLayer.borderColor = Self.cgColor(RGBA(r: style.secondary.r, g: style.secondary.g, b: style.secondary.b, a: 1))
      } else {
        secondaryLayer.backgroundColor = Self.cgColor(style.secondary)
        secondaryLayer.borderWidth = 0
        secondaryLayer.borderColor = nil
      }
      secondaryLayer.opacity = secondary == nil ? 0 : 1
      secondaryRect = secondary
    }
  }

  private static func cgColor(_ c: RGBA) -> CGColor {
    CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
  }
}
