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

  // MARK: presenter

  static let keyA = DisplayKey.uuid("00000000-0000-0000-0000-00000000000A")
  static let keyB = DisplayKey.uuid("00000000-0000-0000-0000-00000000000B")
  static let frameA = CGRect(x: 0, y: 0, width: 1440, height: 900)
  static let frameB = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

  static func display(_ key: DisplayKey, _ frame: CGRect, scale: Double) -> DisplaySnapshot {
    DisplaySnapshot(
      key: key, frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 20), scale: scale, isMain: key == keyA,
      mirrorOf: nil, name: "test", resolution: frame.size)
  }

  static func topology(_ displays: [DisplaySnapshot]) -> TopologySnapshot {
    TopologySnapshot(displays: displays, separateSpaces: true, primaryFrame: frameA)
  }

  static let twoDisplays = topology([display(keyA, frameA, scale: 2), display(keyB, frameB, scale: 1)])

  static func scene(_ displays: [DisplaySnapshot], zonesPerDisplay: Int = 2) -> OverlayScene {
    let layouts = displays.map { d -> ResolvedLayout in
      let width = d.visibleFrame.width / Double(zonesPerDisplay)
      let zones = (1...zonesPerDisplay).map { n in
        Zone(
          number: n, path: NodePath(steps: []),
          frame: CGRect(
            x: d.visibleFrame.minX + Double(n - 1) * width, y: d.visibleFrame.minY, width: width,
            height: d.visibleFrame.height))
      }
      return ResolvedLayout(
        layoutID: LayoutID(rawValue: "grid"), display: d.key, visibleFrame: d.visibleFrame,
        layoutRect: d.visibleFrame, scale: d.scale, zones: zones)
    }
    return OverlayScene(
      layouts: layouts,
      appearance: Appearance(
        fill: RGBA(r: 0.2, g: 0.4, b: 0.8, a: 1), opacity: 0.1, defaultInsets: Insets(margin: 0, gap: 0)),
      options: AccessibilityOptions(reduceTransparency: false, reduceMotion: false))
  }

  @Test func presenterOrdersFrontOncePerSession() throws {
    let topology = Self.twoDisplays
    let presenter = PanelOverlayPresenter(topology: { topology })
    presenter.show(Self.scene(topology.displays))
    for key in [Self.keyA, Self.keyB] {
      let panel = try #require(presenter.panel(for: key))
      #expect(panel.orderFrontCount == 1)
      #expect(panel.isVisible)
    }
    for n in 1...5 {
      presenter.highlight(Highlight(display: Self.keyA, primary: [n % 2 + 1], secondary: [], dimAll: false))
    }
    presenter.highlight(Highlight(display: nil, primary: [], secondary: [], dimAll: true))
    for key in [Self.keyA, Self.keyB] {
      #expect(try #require(presenter.panel(for: key)).orderFrontCount == 1)
    }
    presenter.hide()
    presenter.show(Self.scene(topology.displays))
    for key in [Self.keyA, Self.keyB] {
      #expect(try #require(presenter.panel(for: key)).orderFrontCount == 2)
    }
    // reassert re-orders front while the session is active, and only then.
    presenter.reassert()
    #expect(try #require(presenter.panel(for: Self.keyA)).orderFrontCount == 3)
    presenter.hide()
    presenter.reassert()
    #expect(try #require(presenter.panel(for: Self.keyA)).orderFrontCount == 3)
  }

  @Test func presenterReusesPanels() throws {
    let topology = Self.twoDisplays
    let presenter = PanelOverlayPresenter(topology: { topology })
    let scene = Self.scene(topology.displays)
    // Before any session a highlight is a no-op and creates nothing.
    presenter.highlight(Highlight(display: Self.keyA, primary: [1], secondary: [], dimAll: false))
    #expect(presenter.panel(for: Self.keyA) == nil)

    presenter.show(scene)
    let first = try [Self.keyA, Self.keyB].map { try #require(presenter.panel(for: $0)) }
    let views = try [Self.keyA, Self.keyB].map { try #require(presenter.layerView(for: $0)) }
    presenter.hide()
    for panel in first { #expect(!panel.isVisible) }
    #expect(presenter.panel(for: Self.keyA) === first[0])

    // After hide, highlight does not repaint or order anything.
    let before = views[0].fillLayer(1)?.backgroundColor
    presenter.highlight(Highlight(display: Self.keyA, primary: [1], secondary: [], dimAll: false))
    #expect(views[0].fillLayer(1)?.backgroundColor == before)
    for panel in first { #expect(!panel.isVisible) }

    presenter.show(scene)
    let second = try [Self.keyA, Self.keyB].map { try #require(presenter.panel(for: $0)) }
    #expect(second[0] === first[0])
    #expect(second[1] === first[1])
    let reusedView = try #require(presenter.layerView(for: Self.keyA))
    #expect(reusedView === views[0])
    for panel in second { #expect(panel.isVisible) }

    // orderOut hides but keeps the panels; the next show reuses them.
    presenter.orderOut()
    for panel in second { #expect(!panel.isVisible) }
    #expect(presenter.panel(for: Self.keyB) === first[1])
    presenter.reassert()
    for panel in second { #expect(!panel.isVisible) }
    presenter.show(scene)
    #expect(presenter.panel(for: Self.keyA) === first[0])
  }

  @Test func resizeOnTopologyChange() throws {
    let topology = Self.twoDisplays
    let presenter = PanelOverlayPresenter(topology: { topology })
    presenter.show(Self.scene(topology.displays))
    let panelA = try #require(presenter.panel(for: Self.keyA))
    let panelB = try #require(presenter.panel(for: Self.keyB))

    // The same Display at a new resolution: same panel instance, new frame, layers redrawn (AC-061).
    let newFrameA = CGRect(x: -100, y: -50, width: 1728, height: 1117)
    let resized = Self.topology([Self.display(Self.keyA, newFrameA, scale: 2), Self.display(Self.keyB, Self.frameB, scale: 1)])
    presenter.resize(to: resized)
    #expect(presenter.panel(for: Self.keyA) === panelA)
    #expect(panelA.frame == newFrameA)
    #expect(panelA.isVisible)
    #expect(panelA.orderFrontCount == 1)
    let view = try #require(presenter.layerView(for: Self.keyA))
    #expect(view.frame.size == newFrameA.size)
    let zone = try #require(view.fillLayer(1))
    // Zone 1 was resolved at (0, 20, 720, 860) in AppKit global space; its local rect follows the new panel origin.
    #expect(zone.frame == CGRect(x: 100, y: 70, width: 720, height: 860))

    // A scene resolved for the new geometry re-applies against the new frame.
    presenter.show(Self.scene(resized.displays))
    let layer = try #require(presenter.layerView(for: Self.keyA)?.fillLayer(2))
    #expect(layer.frame.maxX == resized.displays[0].visibleFrame.maxX - newFrameA.minX)

    // A removed Display: its panel is ordered out and dropped; the other keeps its instance.
    let onlyB = Self.topology([Self.display(Self.keyB, Self.frameB, scale: 1)])
    presenter.resize(to: onlyB)
    #expect(presenter.panel(for: Self.keyA) == nil)
    #expect(!panelA.isVisible)
    #expect(presenter.panel(for: Self.keyB) === panelB)
    #expect(panelB.isVisible)

    // An added Display gets a new panel, hidden until the next show.
    let keyC = DisplayKey.uuid("00000000-0000-0000-0000-00000000000C")
    let frameC = CGRect(x: -1280, y: 0, width: 1280, height: 800)
    let withC = Self.topology([Self.display(Self.keyB, Self.frameB, scale: 1), Self.display(keyC, frameC, scale: 2)])
    presenter.resize(to: withC)
    let panelC = try #require(presenter.panel(for: keyC))
    #expect(panelC.frame == frameC)
    #expect(!panelC.isVisible)
    #expect(panelC !== panelA)
  }
}
