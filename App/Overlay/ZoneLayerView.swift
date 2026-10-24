import AppKit
import ZonesCore
import ZonesLayout
import ZonesWindowing

/// Renders one `PanelModel` with persistent `CALayer`s: a fill and a label per Zone, plus one highlight and one
/// secondary layer. No `draw(_:)`; every mutation happens inside a `CATransaction` with actions disabled.
@MainActor
final class ZoneLayerView: NSView {
  private let highlightLayer = CALayer()
  private let secondaryLayer = CALayer()
  private var fillLayers: [Int: CALayer] = [:]
  private var labelLayers: [Int: CATextLayer] = [:]
  private var applied: PanelModel?
  private let scale: Double

  init(frame: CGRect, scale: Double) {
    self.scale = scale
    super.init(frame: frame)
    wantsLayer = true
    layerContentsRedrawPolicy = .never
    for layer in [highlightLayer, secondaryLayer] {
      layer.contentsScale = scale
      layer.isOpaque = false
      layer.opacity = 0
      self.layer?.addSublayer(layer)
    }
  }

  @available(*, unavailable) required init?(coder: NSCoder) { nil }

  override func isAccessibilityElement() -> Bool { false }
  override func accessibilityChildren() -> [Any]? { [] }

  /// Every layer this view owns, for tests.
  var allLayers: [CALayer] {
    [highlightLayer, secondaryLayer] + fillLayers.values.sorted { $0.zPosition < $1.zPosition }
      + labelLayers.values.sorted { $0.zPosition < $1.zPosition }
  }

  func apply(_ model: PanelModel) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    for zone in model.zones where fillLayers[zone.number] == nil {
      let fill = CALayer()
      fill.contentsScale = scale
      let label = CATextLayer()
      label.contentsScale = zone.label.contentsScale
      layer?.addSublayer(fill)
      layer?.addSublayer(label)
      fillLayers[zone.number] = fill
      labelLayers[zone.number] = label
    }
    applied = model
  }
}
