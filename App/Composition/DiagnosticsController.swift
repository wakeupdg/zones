import Foundation
import ZonesCore
import ZonesWindowing

/// Copy Diagnostics (AC-154): the report text is shown first; it reaches the pasteboard only after the user
/// confirms the preview. The report carries no window text of any kind (LI-003).
@MainActor
final class DiagnosticsController {
  private let appState: AppState
  private let topology: TopologyDriver
  private let permission: PermissionDriver
  private let presenter: any DiagnosticsPresenter
  private let bundle: @Sendable () -> BundleInfo

  init(
    appState: AppState, topology: TopologyDriver, permission: PermissionDriver,
    presenter: any DiagnosticsPresenter, bundle: @escaping @Sendable () -> BundleInfo
  ) {
    self.appState = appState
    self.topology = topology
    self.permission = permission
    self.presenter = presenter
    self.bundle = bundle
  }

  func report() -> DiagnosticsReport {
    Diagnostics.report(
      bundle: bundle(), permission: permission.state, tap: permission.tap, topology: topology.snapshot,
      assignments: appState.assignments, prefs: appState.preferences, ring: Log.shared.ring())
  }

  /// `[.preview, .copy]` in that order; a declined preview stops before the copy.
  func copyDiagnostics() {
    for effect in Diagnostics.effects(for: report()) {
      switch effect {
      case .preview(let text): if !presenter.showPreview(text) { return }
      case .copy(let text): presenter.copy(text)
      }
    }
  }
}
