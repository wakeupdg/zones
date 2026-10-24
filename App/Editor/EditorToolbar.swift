import AppKit
import ZonesCore
import ZonesLayout

/// Pure model behind the toolbar controls. Everything the controls decide lives here so AppTests can reach it
/// without AppKit; the reducer still owns every editing rule.
enum EditorToolbarModel {
  struct DisplayChoice: Hashable {
    var key: DisplayKey
    var name: String
    var isConnected: Bool
  }

  /// Connected Displays first (topology order), then disconnected ones known only from Assignment records
  /// (ADR-0012), by stored `displayName` then UUID so the order is stable.
  static func displayChoices(topology: TopologySnapshot, assignments: [String: Assignment]) -> [DisplayChoice] {
    let connected = topology.displays.map { DisplayChoice(key: $0.key, name: $0.name, isConnected: true) }
    let disconnected = assignments
      .filter { topology.display(.uuid($0.key)) == nil }
      .sorted { ($0.value.displayName, $0.key) < ($1.value.displayName, $1.key) }
      .map { DisplayChoice(key: .uuid($0.key), name: $0.value.displayName, isConnected: false) }
    return connected + disconnected
  }

  /// Picking a Display. A dirty draft answers `promptUnsaved` from the reducer; nothing is switched yet.
  static func pickDisplay(_ key: DisplayKey) -> EditorEvent { .switchDisplay(key, confirmed: false) }

  /// The user confirmed the unsaved-changes prompt: switch and keep the draft.
  static func confirmSwitch(to key: DisplayKey) -> EditorEvent { .switchDisplay(key, confirmed: true) }
}
