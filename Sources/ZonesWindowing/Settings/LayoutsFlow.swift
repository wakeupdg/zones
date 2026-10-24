import Foundation
import ZonesCore
import ZonesLayout

/// Logic behind Settings > Layouts: export, import, and the per-Layout and per-Display actions. A value type
/// with no UI; the App's controller owns one, publishes it, and runs the file panels. Every persisting call
/// writes through `DocumentStore` (layouts.json and assignments.json) and leaves the state untouched on failure.
public struct LayoutsFlow {
  public internal(set) var store: LayoutStore
  public internal(set) var assignments: [String: Assignment]
  /// Layouts picked for Displays whose key is not persistable ("not saved"); lost at quit.
  public internal(set) var session: [DisplayKey: LayoutID]
  /// An import that is decoded and waiting for the Merge or Replace choice.
  public internal(set) var pendingImport: PendingImport?
  /// Inline text for the last refused import, shown until the next successful one.
  public internal(set) var importError: String?
  /// What the last applied import did, for the confirmation line.
  public internal(set) var lastImport: ImportReport?

  let documents: DocumentStore

  public init(
    documents: DocumentStore, layouts: ZonesDocument, assignments: [String: Assignment], defaults: Insets,
    session: [DisplayKey: LayoutID] = [:]
  ) {
    self.documents = documents
    store = LayoutStore(document: layouts, defaults: defaults)
    self.assignments = assignments
    self.session = session
  }

  /// All custom Layouts and Assignments, or one Layout and the Assignments that use it.
  public func exportDocument(only: LayoutID?) -> ZonesDocument {
    ImportExport.export(store, assignments: assignments, only: only)
  }

  /// Writes the export, encoded by the one document codec, to `url`. Atomic: a failure leaves any old file.
  public func writeExport(only: LayoutID?, to url: URL, fs: any FileSystem) throws(DocumentError) {
    do {
      try fs.writeAtomic(try exportDocument(only: only).encoded(for: nil), to: url)
    } catch {
      throw .io(String(describing: error))
    }
  }
}

/// A decoded import file waiting for the Merge or Replace choice.
public struct PendingImport: Hashable, Sendable {
  public var document: ZonesDocument
  public var fileName: String
}

/// The outcome of an applied import.
public struct ImportReport: Hashable, Sendable {
  public var mode: ImportMode
  public var backup: String?
  /// Imported Assignment keys whose Display is not attached; kept dormant, not dropped.
  public var dormant: [String]
}
