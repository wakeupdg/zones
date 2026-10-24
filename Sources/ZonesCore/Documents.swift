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
    assignments = try c.decodeIfPresent([String: Assignment].self, forKey: .assignments) ?? [:]
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(version, forKey: .version)
    try c.encode(layouts, forKey: .layouts)
    try c.encode(assignments, forKey: .assignments)
  }
}
