import Foundation
import ZonesCore
import ZonesLayout

/// What the Layouts pane lists (US-096, US-099). Data and titles only; the buttons belong to Settings.
public struct LayoutsPaneModel: Hashable, Sendable {
  public enum Row: Hashable, Sendable {
    case attached(DisplaySnapshot, LayoutID, unstable: Bool)
    case disconnected(key: String, Assignment, copyTargets: [DisplayKey])
  }

  public static let notSavedLabel = "not saved"
  public static let forgetTitle = "Forget"

  public static func copyTitle(_ target: DisplaySnapshot) -> String { "Copy Assignment to \(target.name)" }

  public static func rows(
    _ t: TopologySnapshot, assignments: [String: Assignment], session: [DisplayKey: LayoutID]
  ) -> [Row] {
    let attached: [Row] = t.displays.map { display in
      let unstable: Bool
      if case .unstable = display.key { unstable = true } else { unstable = false }
      return .attached(
        display, AssignmentLookup.layoutID(for: display.key, in: assignments, session: session), unstable: unstable)
    }
    var attachedUUIDs = Set<String>()
    var copyTargets: [DisplayKey] = []
    for display in t.displays {
      if case .uuid(let uuid) = display.key {
        attachedUUIDs.insert(uuid)
        copyTargets.append(display.key)
      }
    }
    let disconnected: [Row] = assignments.filter { !attachedUUIDs.contains($0.key) }
      .sorted { ($0.value.displayName, $0.key) < ($1.value.displayName, $1.key) }
      .map { .disconnected(key: $0.key, $0.value, copyTargets: copyTargets) }
    return attached + disconnected
  }
}
