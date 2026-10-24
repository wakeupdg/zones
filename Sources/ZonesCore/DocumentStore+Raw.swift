import Foundation

/// Raw bytes of a `DocumentKind` file, for documents that are not a `ZonesDocument` (the Enhanced
/// UI recovery record). Same directory, same atomic write as the typed API.
extension DocumentStore {
  /// The file's bytes, or `nil` when it is missing or unreadable.
  public func loadRaw(_ kind: DocumentKind) -> Data? {
    guard fs.exists(url(kind)) else { return nil }
    return try? fs.read(url(kind))
  }

  public func saveRaw(_ data: Data, as kind: DocumentKind) throws {
    try fs.writeAtomic(data, to: url(kind))
  }

  /// Deletes the file. A missing file or a failed delete is not an error.
  public func remove(_ kind: DocumentKind) {
    try? fs.remove(url(kind))
  }
}

/// Backup files that sit beside the documents (import Replace names one before it writes).
extension DocumentStore {
  /// Writes `data` as `name` in the documents directory. `name` must be a plain file name.
  public func saveBackup(_ data: Data, named name: String) throws(DocumentError) {
    guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
      throw .io("invalid backup name \(name)")
    }
    do { try fs.writeAtomic(data, to: directory.appending(path: name)) } catch { throw .io(String(describing: error)) }
  }
}
