import SwiftUI
import ZonesCore
import ZonesWindowing

/// General: two status rows, the Activation and Span modifiers, Re-run onboarding, Launch at Login.
/// Persistence and the AC-087 coercion belong elsewhere; this pane reports changes through `onChange`.
struct GeneralPane: View {
  let permission: () -> PermissionState
  let tap: () -> TapState
  let onRerunOnboarding: () -> Void
  let onChange: (Preferences) -> Void
  let coordinator: LoginItemToggleCoordinator
  /// The controller's current value; other panes change it, so the local copy follows it.
  let external: Preferences

  @State private var prefs: Preferences
  @State private var refreshTick = 0

  init(
    preferences: Preferences, permission: @escaping () -> PermissionState,
    tap: @escaping () -> TapState, onRerunOnboarding: @escaping () -> Void,
    onChange: @escaping (Preferences) -> Void, coordinator: LoginItemToggleCoordinator
  ) {
    _prefs = State(initialValue: preferences)
    external = preferences
    self.permission = permission
    self.tap = tap
    self.onRerunOnboarding = onRerunOnboarding
    self.onChange = onChange
    self.coordinator = coordinator
  }

  var body: some View {
    let rows = GeneralPaneModel.statusRows(permission(), tap: tap())
    let toggle = coordinator.model
    Form {
      Section {
        ForEach(rows, id: \.label) { row in
          LabeledContent(row.label, value: row.value)
        }
        Button("Re-run onboarding", action: onRerunOnboarding)
      }
      .id(refreshTick)
      Section("Modifier keys") {
        modifierRow("Activation", selection: $prefs.activationModifier)
        modifierRow("Span", selection: $prefs.spanModifier)
      }
      Section {
        Toggle(
          "Launch at Login",
          isOn: Binding(get: { toggle.isOn }, set: { coordinator.setOn($0) })
        )
        .disabled(toggle.disabled)
        if let caption = toggle.caption {
          Text(caption).font(.callout).foregroundStyle(.secondary)
        }
        if toggle.showLoginItemsButton {
          Button("Open Login Items Settings") { coordinator.openLoginItemsSettings() }
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      coordinator.refresh()
      refreshTick += 1
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      coordinator.refresh()
      refreshTick += 1
    }
    .onChange(of: prefs) { _, new in onChange(new) }
    .onChange(of: external) { _, new in if new != prefs { prefs = new } }
  }

  private func modifierRow(_ title: String, selection: Binding<Modifier>) -> some View {
    LabeledContent(title) {
      HStack {
        KeyCapView(modifier: selection.wrappedValue)
        Picker(title, selection: selection) {
          ForEach(Modifier.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
      }
    }
  }
}
