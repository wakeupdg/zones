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
