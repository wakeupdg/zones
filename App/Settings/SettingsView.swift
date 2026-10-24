import Observation
import SwiftUI
import ZonesCore
import ZonesWindowing

enum SettingsTab: String, CaseIterable, Hashable {
  case general, layouts, shortcuts, appearance, exclusions, about

  var title: String { rawValue.capitalized }
}

/// The selected tab, shared with the window controller so `show(tab:)` can switch it.
@MainActor @Observable
final class SettingsSelection {
  var tab: SettingsTab = .general
}

struct SettingsView: View {
  @Bindable var selection: SettingsSelection
  let environment: SettingsEnvironment
  let about: AboutModel
  let permission: () -> PermissionState
  let tap: () -> TapState
  let onRerunOnboarding: () -> Void
  let coordinator: LoginItemToggleCoordinator

  var body: some View {
    TabView(selection: $selection.tab) {
      GeneralPane(
        preferences: environment.preferences.preferences, permission: permission, tap: tap,
        onRerunOnboarding: onRerunOnboarding,
        // General owns only the two modifiers; the other panes' fields must not be overwritten by its copy.
        onChange: { new in
          environment.preferences.update {
            $0.activationModifier = new.activationModifier
            $0.spanModifier = new.spanModifier
          }
        },
        coordinator: coordinator
      )
      .tabItem { Text(SettingsTab.general.title) }.tag(SettingsTab.general)
      LayoutsPane(controller: environment.layouts, topology: environment.topology)
        .tabItem { Text(SettingsTab.layouts.title) }.tag(SettingsTab.layouts)
      ShortcutsPane(model: environment.shortcuts)
        .tabItem { Text(SettingsTab.shortcuts.title) }.tag(SettingsTab.shortcuts)
      AppearancePane(model: environment.appearance)
        .tabItem { Text(SettingsTab.appearance.title) }.tag(SettingsTab.appearance)
      ExclusionsPane(model: environment.exclusions)
        .tabItem { Text(SettingsTab.exclusions.title) }.tag(SettingsTab.exclusions)
      AboutPane(model: about).tabItem { Text(SettingsTab.about.title) }.tag(SettingsTab.about)
    }
    .frame(minWidth: 520, minHeight: 360)
  }
}
