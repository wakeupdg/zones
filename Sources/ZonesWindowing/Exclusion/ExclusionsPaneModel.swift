import Foundation

/// Model behind the Exclusions pane. Exclusions are a set of bundle identifiers (AC-142), never names.
public enum ExclusionsPaneModel {
  public struct Row: Hashable, Sendable {
    public var name: String
    public var bundleID: String
    public init(name: String, bundleID: String) {
      self.name = name
      self.bundleID = bundleID
    }
  }

  /// One row per bundle id. `name` is `names[bundleID]`, or the bundle id when absent. Sorted by name
  /// (case-insensitive), then bundle id.
  public static func rows(_ exclusions: Set<String>, names: [String: String]) -> [Row] {
    exclusions
      .map { Row(name: names[$0] ?? $0, bundleID: $0) }
      .sorted { lhs, rhs in
        let order = lhs.name.caseInsensitiveCompare(rhs.name)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.bundleID < rhs.bundleID
      }
  }

  public static func add(bundleID: String, to exclusions: inout Set<String>) {
    exclusions.insert(bundleID)
  }

  /// Bundle identifier of the app bundle at `url`; nil when it is not a bundle or has no identifier.
  public static func bundleID(forAppAt url: URL) -> String? {
    Bundle(url: url)?.bundleIdentifier
  }

  /// Adds the bundle identifier of the app at `url`. False, and nothing stored, when it has none.
  @discardableResult
  public static func add(appAt url: URL, to exclusions: inout Set<String>) -> Bool {
    guard let id = bundleID(forAppAt: url), !id.isEmpty else { return false }
    add(bundleID: id, to: &exclusions)
    return true
  }
}
