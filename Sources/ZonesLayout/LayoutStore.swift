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

  /// Custom Layouts only; Assignments live in their own document.
  public var document: ZonesDocument {
    ZonesDocument(version: Constants.documentVersion, layouts: custom, assignments: [:])
  }
}
