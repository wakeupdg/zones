import Foundation
import ZonesCore

/// Production: the App's PanelOverlayPresenter. Fake: FakeOverlayPresenter.
public protocol OverlayPresenter: Sendable {
  @MainActor func show(_ scene: OverlayScene)
  @MainActor func highlight(_ h: Highlight)
  @MainActor func hide()
  @MainActor func reassert()
  @MainActor func orderOut()
  @MainActor func resize(to snapshot: TopologySnapshot)
}
