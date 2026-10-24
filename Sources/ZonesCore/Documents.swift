import Foundation

/// layouts.json carries layouts; assignments.json carries assignments; an export may carry both.
public struct ZonesDocument: Hashable, Codable, Sendable {
  public var version: Int
  /// Custom layouts only.
  public var layouts: [Layout]
  /// Key = display UUID.
  public var assignments: [String: Assignment]

  public init(
    version: Int = Constants.documentVersion, layouts: [Layout] = [],
    assignments: [String: Assignment] = [:]
  ) {
    self.version = version
    self.layouts = layouts
    self.assignments = assignments
  }

  private enum CodingKeys: String, CodingKey { case version, layouts, assignments }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decode(Int.self, forKey: .version)
    layouts = try c.decodeIfPresent([Layout].self, forKey: .layouts) ?? []
    let decoded = try c.decodeIfPresent([String: Assignment].self, forKey: .assignments) ?? [:]
    for key in decoded.keys where UUID(uuidString: key) == nil { throw DocumentError.nonUUIDKey(key) }
    assignments = decoded
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(version, forKey: .version)
    try c.encode(layouts, forKey: .layouts)
    try c.encode(assignments, forKey: .assignments)
  }

  /// The one JSON encoder for disk and export: sorted keys so bytes are stable (ADR-0017).
  /// `layouts.json` writes `version` and `layouts`; `assignments.json` writes `version` and `assignments`;
  /// `nil` (export) and the recovery kind write both.
  public func encoded(for kind: DocumentKind?) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    switch kind {
    case .layouts: return try encoder.encode(KindView(version: version, layouts: layouts, assignments: nil))
    case .assignments: return try encoder.encode(KindView(version: version, layouts: nil, assignments: assignments))
    case .recovery, nil: return try encoder.encode(self)
    }
  }

  private struct KindView: Encodable {
    var version: Int
    var layouts: [Layout]?
    var assignments: [String: Assignment]?
  }
}

public enum DocumentKind: String, Sendable {
  case layouts = "layouts.json", assignments = "assignments.json", recovery = "enhanced-ui-recovery.json"
}

public enum LoadResult: Hashable, Sendable {
  case loaded(ZonesDocument)
  case migrated(ZonesDocument, from: Int, backup: String)
  case defaults(quarantined: String)
  case newerLeftUntouched(version: Int)
}

/// Directory = ~/Library/Application Support/Zones. `load`, `save` and `backupName` are added by the persistence ticket.
public struct DocumentStore: Sendable {
  let fs: any FileSystem
  let directory: URL
  let clock: any Clock

  public init(fs: any FileSystem, directory: URL, clock: any Clock) {
    self.fs = fs
    self.directory = directory
    self.clock = clock
  }
}

/// `migrate(_:)` is added by the persistence ticket (golden fixtures per version, AC-152).
public enum Migrator {}
