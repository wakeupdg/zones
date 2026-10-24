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
  let preferences: Preferences
  let about: AboutModel
  let permission: () -> PermissionState
  let tap: () -> TapState
  let onRerunOnboarding: () -> Void
  let onChange: (Preferences) -> Void
  let coordinator: LoginItemToggleCoordinator

  var body: some View {
    TabView(selection: $selection.tab) {
      GeneralPane(
        preferences: preferences, permission: permission, tap: tap,
        onRerunOnboarding: onRerunOnboarding, onChange: onChange, coordinator: coordinator
      )
      .tabItem { Text(SettingsTab.general.title) }.tag(SettingsTab.general)
      LayoutsPlaceholder().tabItem { Text(SettingsTab.layouts.title) }.tag(SettingsTab.layouts)
      ShortcutsPlaceholder().tabItem { Text(SettingsTab.shortcuts.title) }.tag(SettingsTab.shortcuts)
      AppearancePlaceholder().tabItem { Text(SettingsTab.appearance.title) }.tag(SettingsTab.appearance)
      ExclusionsPlaceholder().tabItem { Text(SettingsTab.exclusions.title) }.tag(SettingsTab.exclusions)
      AboutPane(model: about).tabItem { Text(SettingsTab.about.title) }.tag(SettingsTab.about)
    }
    .frame(minWidth: 520, minHeight: 360)
  }
}

private struct LayoutsPlaceholder: View {
  var body: some View { Text("Layouts arrive in a later ticket.") }
}
private struct ShortcutsPlaceholder: View {
  var body: some View { Text("Shortcuts arrive in a later ticket.") }
}
private struct AppearancePlaceholder: View {
  var body: some View { Text("Appearance arrives in a later ticket.") }
}
private struct ExclusionsPlaceholder: View {
  var body: some View { Text("Exclusions arrive in a later ticket.") }
}
