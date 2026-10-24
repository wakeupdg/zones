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
  var defaults: Insets

  public init(
    documents: DocumentStore, layouts: ZonesDocument, assignments: [String: Assignment], defaults: Insets,
    session: [DisplayKey: LayoutID] = [:]
  ) {
    self.documents = documents
    self.defaults = defaults
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

// MARK: Import

extension LayoutsFlow {
  /// Decodes `data` with the one document decoder. A readable file becomes `pendingImport`, waiting for the
  /// Merge or Replace choice; a refusal sets `importError` and changes nothing else (AC-151).
  public mutating func beginImport(_ data: Data, fileName: String) {
    switch Migrator.migrate(data) {
    case .success(let (document, _)):
      pendingImport = PendingImport(document: document, fileName: fileName)
      importError = nil
    case .failure(let error):
      pendingImport = nil
      importError = error.message
    }
  }

  /// Dismisses the sheet; nothing is written.
  public mutating func cancelImport() { pendingImport = nil }

  /// The backup file Replace would write, for the sheet to show before it writes. nil without a pending file
  /// or when the file would be refused.
  public func replaceBackupName(now: TimeInterval) -> String? {
    guard let pending = pendingImport,
      case .applied(_, let backup, _) = ImportExport.importDocument(
        pending.document, into: currentDocument, mode: .replace, attached: [], newID: { LayoutID(rawValue: "") },
        now: now)
    else { return nil }
    return backup
  }

  /// Applies the pending import in `mode`. Replace writes the backup first. Both documents are saved; on any
  /// refusal or write failure the state and the files stay as they were, `importError` says why, and the sheet
  /// stays open. Returns false when nothing was applied.
  @discardableResult
  public mutating func applyImport(
    _ mode: ImportMode, attached: Set<String>, newID: () -> LayoutID = { LayoutID(rawValue: UUID().uuidString) },
    now: TimeInterval
  ) -> Bool {
    guard let pending = pendingImport else { return false }
    switch ImportExport.importDocument(
      pending.document, into: currentDocument, mode: mode, attached: attached, newID: newID, now: now)
    {
    case .refused(let error):
      importError = error.message
      return false
    case .applied(let document, let backup, let dormant):
      do {
        if let backup { try documents.saveBackup(currentDocument.encoded(for: nil), named: backup) }
        try persist(layouts: document.layouts, assignments: document.assignments)
      } catch let error as DocumentError {
        importError = error.message
        return false
      } catch {
        importError = DocumentError.io(String(describing: error)).message
        return false
      }
      store = LayoutStore(document: document, defaults: defaults)
      assignments = document.assignments
      pendingImport = nil
      importError = nil
      lastImport = ImportReport(mode: mode, backup: backup, dormant: dormant)
      return true
    }
  }

  /// Custom Layouts and every Assignment as one document, the shape Import compares against.
  var currentDocument: ZonesDocument {
    ZonesDocument(version: Constants.documentVersion, layouts: store.custom, assignments: assignments)
  }

  /// Saves layouts.json then assignments.json. If the second write fails the first is put back.
  func persist(layouts: [Layout], assignments: [String: Assignment]) throws(DocumentError) {
    let old = ZonesDocument(layouts: store.custom)
    try documents.save(ZonesDocument(layouts: layouts), as: .layouts)
    do {
      try documents.save(ZonesDocument(assignments: assignments), as: .assignments)
    } catch {
      try? documents.save(old, as: .layouts)
      throw error
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
