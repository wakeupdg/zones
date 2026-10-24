import ZonesCore

/// The in-memory truth for Layouts. Built-ins are regenerated from the Appearance default Insets and never
/// persisted; custom Layouts carry their own explicit Insets. Callers persist `document` through `DocumentStore`.
public struct LayoutStore: Hashable, Sendable {
  public private(set) var builtIns: [Layout]
  public private(set) var custom: [Layout]

  public init(document: ZonesDocument, defaults: Insets) {
    builtIns = Templates.all(insets: defaults)
    custom = document.layouts.filter { $0.builtIn == nil }
  }

  /// The built-in or custom Layout with `id`.
  public func layout(_ id: LayoutID) -> Layout? {
    builtIns.first { $0.id == id } ?? custom.first { $0.id == id }
  }

  /// Regenerates every built-in with `i`; custom Layouts are untouched (AC-117).
  public mutating func setDefaults(_ i: Insets) {
    builtIns = Templates.all(insets: i)
  }

  /// Adds a custom Layout, or replaces the one with the same id in place. Built-ins cannot be upserted.
  public mutating func upsert(_ l: Layout) {
    guard l.builtIn == nil, !l.id.rawValue.hasPrefix("builtin:") else { return }
    if let index = custom.firstIndex(where: { $0.id == l.id }) {
      custom[index] = l
    } else {
      custom.append(l)
    }
  }

  /// Custom Layouts only; Assignments live in their own document.
  public var document: ZonesDocument {
    ZonesDocument(version: Constants.documentVersion, layouts: custom, assignments: [:])
  }
}
