import Foundation
import ZonesCore

public enum ImportMode: Hashable, Sendable { case merge, replace }

public enum ImportResult: Hashable, Sendable {
  case applied(ZonesDocument, backup: String?, dormant: [String])
  case refused(DocumentError)
}

public enum ImportExport {
  /// All custom Layouts and all `assignments`, or just Layout `only` and the Assignments that reference it.
  /// A built-in or unknown id yields an empty `layouts` array. Built-ins are never exported.
  public static func export(
    _ store: LayoutStore, assignments: [String: Assignment], only: LayoutID?
  ) -> ZonesDocument {
    guard let only else {
      return ZonesDocument(version: Constants.documentVersion, layouts: store.custom, assignments: assignments)
    }
    return ZonesDocument(
      version: Constants.documentVersion, layouts: store.custom.filter { $0.id == only },
      assignments: assignments.filter { $0.value.layout == only })
  }

  /// Pure import: the caller writes only on `.applied`.
  /// Merge keeps current Layouts and Assignments, renames name collisions with a numeric suffix and gives
  /// colliding ids fresh ones. Replace returns the incoming document whole and names a backup of both current
  /// documents, stamped like `DocumentStore.backupName`. `dormant` lists the imported keys in the result that are
  /// not in `attached`, sorted.
  public static func importDocument(
    _ incoming: ZonesDocument, into current: ZonesDocument, mode: ImportMode, attached: Set<String>,
    newID: () -> LayoutID, now: TimeInterval
  ) -> ImportResult {
    switch mode {
    case .merge:
      let (document, imported) = merge(incoming, into: current, newID: newID)
      return .applied(document, backup: nil, dormant: imported.subtracting(attached).sorted())
    case .replace:
      var document = incoming
      document.version = Constants.documentVersion
      return .applied(
        document, backup: "zones.\(stamp(now)).bak",
        dormant: Set(incoming.assignments.keys).subtracting(attached).sorted())
    }
  }

  private static func merge(
    _ incoming: ZonesDocument, into current: ZonesDocument, newID: () -> LayoutID
  ) -> (ZonesDocument, imported: Set<String>) {
    var layouts = current.layouts
    var usedIDs = Set(layouts.map(\.id))
    var usedNames = Set(layouts.map(\.name))
    var remap: [LayoutID: LayoutID] = [:]
    for var layout in incoming.layouts {
      if usedIDs.contains(layout.id) {
        let fresh = newID()
        remap[layout.id] = remap[layout.id] ?? fresh
        layout.id = fresh
      }
      layout.name = uniqueName(layout.name, among: usedNames)
      usedIDs.insert(layout.id)
      usedNames.insert(layout.name)
      layouts.append(layout)
    }
    var assignments = current.assignments
    var imported: Set<String> = []
    for (key, var assignment) in incoming.assignments where assignments[key] == nil {
      if let fresh = remap[assignment.layout] { assignment.layout = fresh }
      assignments[key] = assignment
      imported.insert(key)
    }
    return (ZonesDocument(version: Constants.documentVersion, layouts: layouts, assignments: assignments), imported)
  }

  /// `name`, or `"<name> 2"`, `"<name> 3"` and so on: the first not in `taken`.
  private static func uniqueName(_ name: String, among taken: Set<String>) -> String {
    guard taken.contains(name) else { return name }
    var n = 2
    while taken.contains("\(name) \(n)") { n += 1 }
    return "\(name) \(n)"
  }

  /// `yyyyMMdd-HHmmss` in UTC, the stamp `DocumentStore.backupName` puts in a backup file name.
  private static func stamp(_ now: TimeInterval) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date(timeIntervalSince1970: now))
  }
}
