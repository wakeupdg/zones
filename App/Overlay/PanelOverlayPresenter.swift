import AppKit
import ZonesCore
import ZonesWindowing

/// Drives one reusable `ZoneOverlayPanel` per Display (ADR-0023). Panels are created once and only resized.
///
/// Ordering: `show` calls `orderFrontRegardless()` once per panel per session; `highlight` only repaints layers and
/// never touches window order; `hide`/`orderOut` call `orderOut(nil)`; `reassert` orders front again.
@MainActor
final class PanelOverlayPresenter: OverlayPresenter {
  /// Where the current Display geometry comes from. Production passes `{ displays.snapshot() }`.
  typealias TopologyProvider = @MainActor () -> TopologySnapshot

  /// Zones whose layers each panel builds ahead of the first `show` (a 3x3 grid; bigger layouts build the rest on show).
  static let prebuiltZoneCount = 9

  private let topologyProvider: TopologyProvider
  /// The last snapshot given to `resize(to:)`; wins over the provider until the next `resize`.
  private var topology: TopologySnapshot?
  private var panels: [DisplayKey: ZoneOverlayPanel] = [:]
  private var views: [DisplayKey: ZoneLayerView] = [:]
  private var scene: OverlayScene?
  private var baseModels: [PanelModel] = []
  private var lastHighlight: Highlight?
  private var sessionActive = false
  private var panelsOrderedFront = false

  init(topology: @escaping TopologyProvider) {
    topologyProvider = topology
  }

  convenience init(displays: any DisplayProvider) {
    self.init(topology: { displays.snapshot() })
  }

  // MARK: OverlayPresenter

  func show(_ scene: OverlayScene) {
    endSession()
    let snapshot = currentTopology()
    self.scene = scene
    baseModels = OverlayModel.panels(scene, topology: snapshot)
    lastHighlight = nil
    sessionActive = true
    let shown = Set(baseModels.map(\.display))
    for (key, panel) in panels where !shown.contains(key) { panel.orderOut(nil) }
    for model in baseModels {
      let panel = panel(for: model, scale: scale(of: model, in: snapshot))
      panel.fit(to: model.frame)
    }
    render(snapshot)
    for model in baseModels { panels[model.display]?.orderFrontRegardless() }
    panelsOrderedFront = true
  }

  func highlight(_ h: Highlight) {
    guard sessionActive else { return }
    lastHighlight = h
    render(currentTopology())
  }

  func hide() {
    endSession()
  }

  func reassert() {
    guard sessionActive, panelsOrderedFront else { return }
    for model in baseModels { panels[model.display]?.orderFrontRegardless() }
  }

  func orderOut() {
    for panel in panels.values { panel.orderOut(nil) }
    panelsOrderedFront = false
  }

  func resize(to snapshot: TopologySnapshot) {
    topology = snapshot
    let live = Set(snapshot.displays.map(\.key))
    for key in panels.keys where !live.contains(key) {
      panels.removeValue(forKey: key)?.orderOut(nil)
      views.removeValue(forKey: key)
    }
    for display in snapshot.displays {
      if let panel = panels[display.key] {
        panel.fit(to: display.frame)
      } else {
        _ = makePanel(for: display.key, frame: display.frame, scale: display.scale)
      }
    }
    if !sessionActive {
      for view in views.values { view.prebuild(zoneCount: Self.prebuiltZoneCount) }
    }
    guard sessionActive, let scene else { return }
    baseModels = OverlayModel.panels(scene, topology: snapshot)
    render(snapshot)
  }

  // MARK: tests and wiring

  /// The panel for a Display, if one exists. Panels persist across Drag Sessions.
  func panel(for key: DisplayKey) -> ZoneOverlayPanel? { panels[key] }

  func layerView(for key: DisplayKey) -> ZoneLayerView? { views[key] }

  var isSessionActive: Bool { sessionActive }

  // MARK: private

  private func currentTopology() -> TopologySnapshot { topology ?? topologyProvider() }

  private func endSession() {
    sessionActive = false
    lastHighlight = nil
    scene = nil
    baseModels = []
    orderOut()
  }

  private func scale(of model: PanelModel, in snapshot: TopologySnapshot) -> Double {
    snapshot.display(model.display)?.scale ?? model.zones.first?.label.contentsScale ?? 1
  }

  private func panel(for model: PanelModel, scale: Double) -> ZoneOverlayPanel {
    panels[model.display] ?? makePanel(for: model.display, frame: model.frame, scale: scale)
  }

  private func makePanel(for key: DisplayKey, frame: CGRect, scale: Double) -> ZoneOverlayPanel {
    let panel = ZoneOverlayPanel(screenFrame: frame)
    let view = ZoneLayerView(frame: CGRect(origin: .zero, size: frame.size), scale: scale)
    view.autoresizingMask = [.width, .height]
    panel.contentView = view
    panels[key] = panel
    views[key] = view
    return panel
  }

  /// Paints `baseModels` (with the last Highlight applied) into the layer views. Layers only; no window order.
  private func render(_ snapshot: TopologySnapshot) {
    let models = lastHighlight.map { OverlayModel.apply($0, to: baseModels) } ?? baseModels
    for model in models {
      views[model.display]?.apply(model, scale: scale(of: model, in: snapshot))
    }
  }
}
