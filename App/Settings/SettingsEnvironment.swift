import Foundation
import ZonesCore
import ZonesWindowing

/// Everything the Settings panes share: the one `PreferencesController` and the models built on it.
@MainActor
final class SettingsEnvironment {
  let preferences: PreferencesController
  let layouts: ImportExportController
  let shortcuts: ShortcutsModel
  let appearance: AppearanceModel
  let exclusions: ExclusionsModel
  let topology: () -> TopologySnapshot?

  init(
    preferences: PreferencesController, layouts: ImportExportController, shortcuts: ShortcutsModel,
    exclusions: ExclusionsModel, topology: @escaping () -> TopologySnapshot?
  ) {
    self.preferences = preferences
    self.layouts = layouts
    self.shortcuts = shortcuts
    self.exclusions = exclusions
    self.topology = topology
    appearance = AppearanceModel(preferences: preferences, layouts: layouts)
  }

  /// The production wiring: standard UserDefaults, documents in Application Support, and the Carbon registrar
  /// once the app supplies one (nil until the hotkeys ticket wires it).
  static func live(
    topology: @escaping () -> TopologySnapshot?, permission: @escaping () -> PermissionState,
    registrar: (any HotkeyRegistrar)? = nil
  ) -> SettingsEnvironment {
    let preferences = PreferencesController()
    let layouts = ImportExportController.live(
      defaults: preferences.preferences.appearance.defaultInsets, topology: topology)
    let granted: Bool
    if case .granted = permission() { granted = true } else { granted = false }
    return SettingsEnvironment(
      preferences: preferences, layouts: layouts,
      shortcuts: ShortcutsModel(preferences: preferences, registrar: registrar, granted: granted),
      exclusions: ExclusionsModel(preferences: preferences), topology: topology)
  }
}
