import Observation
import SwiftUI
import ZonesCore
import ZonesWindowing

/// Owns the `ShortcutsFlow`, drives the hotkey registrar for it, and writes every stored change through the
/// `PreferencesController`. With no registrar (the global hotkeys are wired in a later ticket) a chord is
/// treated as registered so the setting still saves.
@MainActor @Observable
final class ShortcutsModel {
  private(set) var flow: ShortcutsFlow

  @ObservationIgnored private let preferences: PreferencesController
  @ObservationIgnored private let registrar: (any HotkeyRegistrar)?

  init(preferences: PreferencesController, registrar: (any HotkeyRegistrar)?, granted: Bool) {
    self.preferences = preferences
    self.registrar = registrar
    flow = ShortcutsFlow(shortcuts: preferences.preferences.shortcuts, granted: granted)
  }

  private var driver: ShortcutsFlow.Driver {
    let registrar = registrar
    return ShortcutsFlow.Driver(
      register: { chord, action in registrar?.register(chord, for: action) ?? .registered },
      unregister: { action in registrar?.unregister(action) })
  }

  func chord(of action: ShortcutAction) -> Chord? { flow.shortcuts.first { $0.action == action }?.chord }

  func record(_ chord: Chord, for action: ShortcutAction) { persist(flow.record(chord, for: action, driver: driver)) }
  func accept(_ action: ShortcutAction) { persist(flow.accept(action, driver: driver)) }
  func clear(_ action: ShortcutAction) { persist(flow.clear(action, driver: driver)) }
  func resetToDefaults() { persist(flow.resetToDefaults(driver: driver)) }

  private func persist(_ shortcuts: [Shortcut]?) {
    guard let shortcuts else { return }
    preferences.update { $0.shortcuts = shortcuts }
  }
}

/// One row per action: its recorder, Clear, and the message the last attempt left; Reset to defaults below.
struct ShortcutsPane: View {
  let model: ShortcutsModel

  var body: some View {
    Form {
      Section {
        ForEach(ShortcutAction.allCases, id: \.self) { action in row(action) }
      }
      Section {
        Button("Reset to defaults") { model.resetToDefaults() }
      }
    }
    .formStyle(.grouped)
  }

  /// The label and controls sit directly in the Form (one centre line, as in the General pane); the message
  /// the last attempt left is its own row below, so it never shifts the label.
  @ViewBuilder
  private func row(_ action: ShortcutAction) -> some View {
    let name = ShortcutsFlow.name(of: action)
    HStack(alignment: .center) {
      Text(name)
      Spacer()
      ChordRecorderView(
        chord: model.chord(of: action), accessibilityName: name, onChord: { model.record($0, for: action) },
        onClear: { model.clear(action) }
      )
      .frame(width: 150, height: 24)
      Button("Clear") { model.clear(action) }.disabled(model.chord(of: action) == nil)
    }
    if let message = model.flow.messages[action] {
      HStack {
        Text(message.text).font(.callout).foregroundStyle(message.kind == .warning ? Color.orange : Color.red)
        if message.needsAccept { Button("Accept") { model.accept(action) } }
      }
    }
  }
}
