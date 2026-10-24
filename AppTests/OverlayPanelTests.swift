import AppKit
import Testing
import ZonesCore
import ZonesLayout
import ZonesWindowing

@testable import Zones

extension NSColor {
  convenience init(_ c: RGBA) { self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a) }
}

@MainActor
@Suite struct OverlayPanelTests {
  static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

  static let key = DisplayKey.uuid("00000000-0000-0000-0000-000000000001")

  static let style = PanelStyle(
    idle: RGBA(r: 0.2, g: 0.4, b: 0.8, a: 0.1), highlight: RGBA(r: 0.5, g: 0.7, b: 1, a: 0.4),
    secondary: RGBA(r: 0.5, g: 0.7, b: 1, a: 0.25), dim: RGBA(r: 0.2, g: 0.4, b: 0.8, a: 0.04),
    animationDuration: nil)

  /// `count` equal columns across the panel frame, as AppKit global rects.
  static func model(
    frame: CGRect = screen, count: Int = 3, style: PanelStyle = style, spanOutline: Bool = false,
    primary: Set<Int> = [], secondary: Set<Int> = [], scale: Double = 2
  ) -> PanelModel {
    let width = frame.width / Double(count)
    let zones = (1...count).map { n -> ZoneDrawing in
      let rect = CGRect(x: frame.minX + Double(n - 1) * width, y: frame.minY + 40, width: width, height: frame.height - 80)
      let fill = primary.contains(n) ? style.highlight : secondary.contains(n) ? style.secondary : style.idle
      let label = ZoneLabel(
        number: n, text: String(n), frame: rect, outline: RGBA(r: 1, g: 1, b: 1, a: 1), contentsScale: scale,
        noChord: n > 9)
      return ZoneDrawing(number: n, rect: rect, fill: fill, label: label)
    }
    return PanelModel(display: key, frame: frame, zones: zones, style: style, spanOutline: spanOutline)
  }

  @Test func configuration() {
    let panel = ZoneOverlayPanel(screenFrame: Self.screen)
    #expect(panel.ignoresMouseEvents)
    #expect(!panel.canBecomeKey)
    #expect(!panel.canBecomeMain)
    #expect(panel.level == .screenSaver)
    #expect(!panel.hasShadow)
    #expect(panel.backgroundColor == .clear)
    #expect(!panel.isOpaque)
    for behavior: NSWindow.CollectionBehavior in [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle] {
      #expect(panel.collectionBehavior.contains(behavior))
    }
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.styleMask.contains(.borderless))
    #expect(panel.frame == Self.screen)
  }

  @Test func notAccessibilityElement() {
    let panel = ZoneOverlayPanel(screenFrame: Self.screen)
    let view = ZoneLayerView(frame: CGRect(origin: .zero, size: Self.screen.size), scale: 2)
    panel.contentView = view
    view.apply(Self.model(primary: [2]))
    #expect(!panel.isAccessibilityElement())
    #expect(!view.isAccessibilityElement())
    #expect(view.accessibilityChildren()?.isEmpty ?? true)
    #expect(view.layer?.sublayers?.isEmpty == false)
    // CALayer exposes no isAccessibilityElement on macOS: assert none is an AX element and none is a view child.
    for layer in view.allLayers { #expect(!(layer is any NSAccessibilityElementProtocol)) }
  }

  @Test func layersMatchModel() throws {
    let frame = CGRect(x: -1440, y: 120, width: 1440, height: 900)  // a Display left of and above the primary
    let model = Self.model(frame: frame, count: 4, primary: [2], scale: 3)
    let view = ZoneLayerView(frame: CGRect(origin: .zero, size: frame.size), scale: 2)
    view.apply(model)
    #expect(view.layer?.sublayers?.count == 4 * 2 + 2)
    #expect(view.zoneNumbers == [1, 2, 3, 4])
    for zone in model.zones {
      let expected = CoordinateSpace.panelLocal(zone.rect, panelFrame: model.frame)
      let fill = try #require(view.fillLayer(zone.number))
      let label = try #require(view.labelLayer(zone.number))
      #expect(fill.frame == expected)
      #expect(fill.contentsScale == 2)
      #expect(fill.backgroundColor == NSColor(zone.fill).cgColor)
      #expect(Double(label.contentsScale) == zone.label.contentsScale)
      #expect(label.frame.midX == expected.midX)
      #expect(label.frame.midY == expected.midY)
      #expect(label.string as? NSAttributedString != nil)
    }
    let first = try #require(model.zones.first)
    #expect(view.highlightLayer.frame == CoordinateSpace.panelLocal(model.zones[1].rect, panelFrame: model.frame))
    #expect(view.highlightLayer.opacity == 1)
    #expect(view.secondaryLayer.opacity == 0)
    #expect(first.number == 1)
  }

  @Test func layersReusedAcrossUpdates() throws {
    let view = ZoneLayerView(frame: CGRect(origin: .zero, size: Self.screen.size), scale: 2)
    view.apply(Self.model(primary: [1]))
    let fills = view.zoneNumbers.compactMap { view.fillLayer($0) }
    let labels = view.zoneNumbers.compactMap { view.labelLayer($0) }
    let highlight = view.highlightLayer
    let secondary = view.secondaryLayer
    let count = view.layer?.sublayers?.count
    let second = Self.model(primary: [3], secondary: [2])
    view.apply(second)
    let sameFills = view.zoneNumbers.compactMap { view.fillLayer($0) }.elementsEqual(fills, by: ===)
    let sameLabels = view.zoneNumbers.compactMap { view.labelLayer($0) }.elementsEqual(labels, by: ===)
    #expect(sameFills)
    #expect(sameLabels)
    #expect(view.highlightLayer === highlight)
    #expect(view.secondaryLayer === secondary)
    #expect(view.layer?.sublayers?.count == count)
    #expect(highlight.frame == CoordinateSpace.panelLocal(second.zones[2].rect, panelFrame: second.frame))
    #expect(fills[0].backgroundColor == NSColor(Self.style.idle).cgColor)
    #expect(fills[2].backgroundColor == NSColor(Self.style.highlight).cgColor)
    // A Zone that disappears loses its layers; the rest stay.
    view.apply(Self.model(count: 2))
    #expect(view.zoneNumbers == [1, 2])
    #expect(view.layer?.sublayers?.count == 2 * 2 + 2)
  }

  @Test func updatesDoNotAnimate() {
    for duration in [nil, 0.12] as [Double?] {
      var style = Self.style
      style.animationDuration = duration
      let view = ZoneLayerView(frame: CGRect(origin: .zero, size: Self.screen.size), scale: 2)
      view.apply(Self.model(style: style))
      let moved = Self.model(style: style, primary: [2])
      view.apply(moved)
      let expected = CoordinateSpace.panelLocal(moved.zones[1].rect, panelFrame: moved.frame)
      let shown = view.highlightLayer.presentation() ?? view.highlightLayer
      #expect(shown.frame == expected)
      #expect(shown.opacity == 1)
      view.apply(Self.model(style: style, primary: [3]))
      for layer in view.allLayers {
        let keys = layer.animationKeys() ?? []
        if duration == nil {
          #expect(keys.isEmpty)
        } else {
          // Only the explicit opacity fade on the highlight layer is allowed; geometry and colors never animate.
          #expect(keys.allSatisfy { $0 == "fade" && layer === view.highlightLayer })
        }
      }
    }
  }

  @Test func spanOutlineRendersAsBorder() {
    let outlined = ZoneLayerView(frame: CGRect(origin: .zero, size: Self.screen.size), scale: 2)
    outlined.apply(Self.model(spanOutline: true, primary: [1], secondary: [2, 3]))
    #expect(outlined.secondaryLayer.borderWidth > 0)
    #expect(outlined.secondaryLayer.borderColor != nil)
    #expect(outlined.secondaryLayer.backgroundColor == nil)
    #expect(outlined.secondaryLayer.opacity == 1)

    let filled = ZoneLayerView(frame: CGRect(origin: .zero, size: Self.screen.size), scale: 2)
    filled.apply(Self.model(spanOutline: false, primary: [1], secondary: [2, 3]))
    #expect(filled.secondaryLayer.borderWidth == 0)
    #expect(filled.secondaryLayer.backgroundColor == NSColor(Self.style.secondary).cgColor)

    // Flipping the option on the same view switches the same layer.
    filled.apply(Self.model(spanOutline: true, primary: [1], secondary: [2, 3]))
    #expect(filled.secondaryLayer.borderWidth > 0)
    #expect(filled.secondaryLayer.backgroundColor == nil)
  }
}
