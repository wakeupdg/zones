import AppKit
import ZonesCore
import ZonesLayout

/// Pure geometry for the editor canvas. The editor never recomputes layout math: every rectangle here is a
/// `ResolvedLayout` frame from `LayoutMath.resolve` (via `EditorState.preview`), only translated into view space.
enum EditorCanvasGeometry {
  struct ZoneRect: Hashable {
    var number: Int
    var path: NodePath
    var rect: CGRect
  }

  /// Each Zone's frame in view coordinates. `contentOrigin` is the screen position (AppKit coordinates, y up) of
  /// the view's bottom-left corner; subtracting it is the only change, so 1 view point is 1 screen point and the
  /// Zones stay on the same screen pixels when the window moves or resizes.
  static func zoneRects(preview: ResolvedLayout, contentOrigin: CGPoint) -> [ZoneRect] {
    preview.zones.map {
      ZoneRect(
        number: $0.number, path: $0.path, rect: $0.frame.offsetBy(dx: -contentOrigin.x, dy: -contentOrigin.y))
    }
  }

  /// One draggable divider: the split node at `path`.
  struct Divider: Hashable {
    var path: NodePath
    var axis: SplitAxis
    /// The split node's whole region in view space (its unit rectangle inside the Layout rectangle).
    var parent: CGRect
    /// A thin rectangle centred on the divider, `hitThickness` wide, for hit-testing and drawing the handle.
    var line: CGRect
  }

  static let hitThickness: CGFloat = 12

  /// Every split node's divider in view space, outermost first.
  static func dividers(layout: Layout, preview: ResolvedLayout, contentOrigin: CGPoint) -> [Divider] {
    let leaves = LayoutMath.unitRects(layout.root)
    var out: [Divider] = []
    func walk(_ node: SplitNode, steps: [Bool]) {
      guard case .split(let axis, let ratio, let first, let second) = node else { return }
      var unit: UnitRect?
      for leaf in leaves where leaf.path.steps.starts(with: steps) {
        unit = unit.map { union($0, leaf.rect) } ?? leaf.rect
      }
      if let unit {
        // Unit space has y down; AppKit y is up, so flip inside the Layout rectangle.
        let lr = preview.layoutRect
        let parentX = lr.minX + unit.x * lr.width - contentOrigin.x
        let parentY = lr.maxY - (unit.y + unit.height) * lr.height - contentOrigin.y
        let parent = CGRect(x: parentX, y: parentY, width: unit.width * lr.width, height: unit.height * lr.height)
        let line: CGRect
        switch axis {
        case .horizontal:
          line = CGRect(
            x: parent.minX + ratio * parent.width - hitThickness / 2, y: parent.minY, width: hitThickness,
            height: parent.height)
        case .vertical:
          line = CGRect(
            x: parent.minX, y: parent.maxY - ratio * parent.height - hitThickness / 2, width: parent.width,
            height: hitThickness)
        }
        out.append(Divider(path: NodePath(steps: steps), axis: axis, parent: parent, line: line))
      }
      walk(first, steps: steps + [false])
      walk(second, steps: steps + [true])
    }
    walk(layout.root, steps: [])
    return out
  }

  private static func union(_ a: UnitRect, _ b: UnitRect) -> UnitRect {
    let minX = min(a.x, b.x)
    let minY = min(a.y, b.y)
    let maxX = max(a.x + a.width, b.x + b.width)
    let maxY = max(a.y + a.height, b.y + b.height)
    return UnitRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  /// The edit a drag of `divider` to `point` (view space) means: `setRatio` with the pointer's fraction of the
  /// parent's extent. Snapping is on unless Option is held (free drag). Range rules belong to the reducer.
  static func event(forDragOf divider: Divider, to point: CGPoint, optionHeld: Bool) -> EditorEvent {
    let ratio: Double
    switch divider.axis {
    case .horizontal: ratio = Double((point.x - divider.parent.minX) / divider.parent.width)
    case .vertical: ratio = Double((divider.parent.maxY - point.y) / divider.parent.height)  // first = top, y up
    }
    return .command(.setRatio(divider.path, ratio, snap: !optionHeld))
  }
}


/// Draws the draft at real scale and turns mouse input into editor events. It fills the window's content view; the
/// window's screen position is read at draw time, so moving or resizing the window never moves the Zones.
@MainActor
final class EditorCanvasView: NSView {
  var state: EditorState? { didSet { needsDisplay = true } }
  var zoneStyle: Appearance {
    didSet { needsDisplay = true }
  }
  var onEvent: (EditorEvent) -> Void = { _ in }

  private var dragged: EditorCanvasGeometry.Divider?
  private var observers: [any NSObjectProtocol] = []

  init(zoneStyle: Appearance) {
    self.zoneStyle = zoneStyle
    super.init(frame: .zero)
  }

  @available(*, unavailable) required init?(coder: NSCoder) { nil }

  override var acceptsFirstResponder: Bool { true }
  override var isOpaque: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  /// Screen position (AppKit coordinates) of this view's bottom-left corner.
  var contentOrigin: CGPoint {
    guard let window else { return .zero }
    return window.convertToScreen(convert(bounds, to: nil)).origin
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    for token in observers { NotificationCenter.default.removeObserver(token) }
    observers = []
    guard let window else { return }
    for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.needsDisplay = true }
        })
    }
  }

  // MARK: drawing

  override func draw(_ dirtyRect: NSRect) {
    guard let state else { return }
    let origin = contentOrigin
    let zones = EditorCanvasGeometry.zoneRects(preview: state.preview, contentOrigin: origin)
    let opacity = min(max(zoneStyle.opacity, 0), 1)
    let fill = Self.color(zoneStyle.fill, alpha: opacity)
    let selectedPath = state.draft.selection

    for zone in zones {
      let selected = selectedPath == zone.path
      let path = NSBezierPath(rect: zone.rect)
      (selected ? Self.color(zoneStyle.fill, alpha: min(opacity + 0.25, 1)) : fill).setFill()
      path.fill()
      if state.warnings.contains(zone.number) {
        // Under the usable size (warnings come from the reducer, never recomputed here).
        NSColor.systemRed.setStroke()
        let warn = NSBezierPath(rect: zone.rect.insetBy(dx: 1, dy: 1))
        warn.lineWidth = 2
        warn.setLineDash([6, 4], count: 2, phase: 0)
        warn.stroke()
      }
      if selected {
        NSColor.controlAccentColor.setStroke()
        let ring = NSBezierPath(rect: zone.rect.insetBy(dx: 1.5, dy: 1.5))
        ring.lineWidth = 3
        ring.stroke()
      }
    }

    for label in LabelModel.labels(state.preview, appearance: zoneStyle) {
      drawLabel(label, origin: origin)
    }

    let dividers = EditorCanvasGeometry.dividers(
      layout: state.draft.layout, preview: state.preview, contentOrigin: origin)
    for divider in dividers {
      let selected = selectedPath == divider.path
      (selected ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.55)).setFill()
      let thickness: CGFloat = selected ? 4 : 2
      let line: CGRect
      switch divider.axis {
      case .horizontal:
        line = CGRect(x: divider.line.midX - thickness / 2, y: divider.line.minY, width: thickness, height: divider.line.height)
      case .vertical:
        line = CGRect(x: divider.line.minX, y: divider.line.midY - thickness / 2, width: divider.line.width, height: thickness)
      }
      NSBezierPath(roundedRect: line, xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }
  }

  private func drawLabel(_ label: ZoneLabel, origin: CGPoint) {
    let frame = label.frame.offsetBy(dx: -origin.x, dy: -origin.y)
    let size = min(max(min(frame.width, frame.height) * 0.3, 14), 160)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: size, weight: .semibold),
      .foregroundColor: Self.color(label.outline, alpha: 1),
    ]
    let text = NSAttributedString(string: label.text, attributes: attributes)
    let box = text.size()
    text.draw(at: CGPoint(x: frame.midX - box.width / 2, y: frame.midY - box.height / 2))
    if label.noChord {
      // Zone 10 and up cannot be addressed by a single digit chord; LabelModel owns the flag.
      let badge = NSAttributedString(
        string: "no chord",
        attributes: [
          .font: NSFont.systemFont(ofSize: 11, weight: .medium),
          .foregroundColor: Self.color(label.outline, alpha: 0.85),
        ])
      let badgeSize = badge.size()
      badge.draw(at: CGPoint(x: frame.midX - badgeSize.width / 2, y: frame.midY - box.height / 2 - badgeSize.height - 2))
    }
  }

  private static func color(_ c: RGBA, alpha: Double) -> NSColor {
    NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
  }

  // MARK: mouse

  private func dividers() -> [EditorCanvasGeometry.Divider] {
    guard let state else { return [] }
    return EditorCanvasGeometry.dividers(layout: state.draft.layout, preview: state.preview, contentOrigin: contentOrigin)
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    guard let state else { return }
    let point = convert(event.locationInWindow, from: nil)
    // Deepest divider first: nested dividers sit on top of their parents' regions.
    if let hit = dividers().last(where: { $0.line.contains(point) }) {
      dragged = hit
      onEvent(.command(.select(hit.path)))
      return
    }
    let zones = EditorCanvasGeometry.zoneRects(preview: state.preview, contentOrigin: contentOrigin)
    if let zone = zones.first(where: { $0.rect.contains(point) }) {
      onEvent(.command(.select(zone.path)))
    } else {
      onEvent(.command(.select(nil)))
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let current = dragged else { return }
    // The divider's region moves with the draft, so re-read it by path for every drag step.
    guard let divider = dividers().first(where: { $0.path == current.path }) else { return }
    let point = convert(event.locationInWindow, from: nil)
    onEvent(EditorCanvasGeometry.event(forDragOf: divider, to: point, optionHeld: event.modifierFlags.contains(.option)))
  }

  override func mouseUp(with event: NSEvent) { dragged = nil }
}
