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
}
