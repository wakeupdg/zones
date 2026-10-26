import Foundation

/// The production `FileSystem`. Writes go to a temporary file and replace the destination in one step,
/// so a failed write leaves the old file intact.
public struct FoundationFileSystem: FileSystem {
  public init() {}

  public func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }

  public func writeAtomic(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  public func move(_ from: URL, to: URL) throws {
    try FileManager.default.createDirectory(
      at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: to.path) { try FileManager.default.removeItem(at: to) }
    try FileManager.default.moveItem(at: from, to: to)
  }

  public func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

  public func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
}
