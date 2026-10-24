import Foundation

/// A UUID string, or `builtin:<template>:<count>`. Encodes as a bare JSON string.
public struct LayoutID: Hashable, Codable, Sendable, RawRepresentable {
  public let rawValue: String

  public init(rawValue: String) { self.rawValue = rawValue }

  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public enum SplitAxis: String, Codable, Sendable {
  /// Side by side: first = left.
  case horizontal
  /// Stacked: first = top.
  case vertical
}

public indirect enum SplitNode: Hashable, Codable, Sendable {
  /// A Zone; no payload, numbers are derived.
  case leaf
  /// `ratio` in (0,1) is the first child's share.
  case split(axis: SplitAxis, ratio: Double, first: SplitNode, second: SplitNode)

  private enum CodingKeys: String, CodingKey { case kind, axis, ratio, first, second }
  private enum Kind: String, Codable { case leaf, split }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    switch try c.decode(Kind.self, forKey: .kind) {
    case .leaf:
      self = .leaf
    case .split:
      self = .split(
        axis: try c.decode(SplitAxis.self, forKey: .axis),
        ratio: try c.decode(Double.self, forKey: .ratio),
        first: try c.decode(SplitNode.self, forKey: .first),
        second: try c.decode(SplitNode.self, forKey: .second))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .leaf:
      try c.encode(Kind.leaf, forKey: .kind)
    case .split(let axis, let ratio, let first, let second):
      try c.encode(Kind.split, forKey: .kind)
      try c.encode(axis, forKey: .axis)
      try c.encode(ratio, forKey: .ratio)
      try c.encode(first, forKey: .first)
      try c.encode(second, forKey: .second)
    }
  }
}

/// false = first, true = second; [] = root.
public struct NodePath: Hashable, Codable, Sendable {
  public var steps: [Bool]
  public init(steps: [Bool]) { self.steps = steps }
}

/// Points.
public struct Insets: Hashable, Codable, Sendable {
  public var margin: Double
  public var gap: Double
  public init(margin: Double, gap: Double) {
    self.margin = margin
    self.gap = gap
  }
}

/// Fractions, each 0...0.45.
public struct Surround: Hashable, Codable, Sendable {
  public var top, left, bottom, right: Double
  public init(top: Double, left: Double, bottom: Double, right: Double) {
    self.top = top
    self.left = left
    self.bottom = bottom
    self.right = right
  }
}

/// Never encoded.
public struct BuiltInRef: Hashable, Sendable {
  public var template: Template
  public var count: Int
  public init(template: Template, count: Int) {
    self.template = template
    self.count = count
  }
}

public struct Layout: Hashable, Codable, Sendable, Identifiable {
  public var id: LayoutID
  public var name: String
  public var root: SplitNode
  /// Explicit on every persisted Layout (never nil).
  public var surround: Surround
  public var insets: Insets
  /// nil for custom; built-ins never reach layouts.json, so this key is never encoded.
  public var builtIn: BuiltInRef?

  public init(
    id: LayoutID, name: String, root: SplitNode, surround: Surround, insets: Insets,
    builtIn: BuiltInRef? = nil
  ) {
    self.id = id
    self.name = name
    self.root = root
    self.surround = surround
    self.insets = insets
    self.builtIn = builtIn
  }

  private enum CodingKeys: String, CodingKey { case id, name, root, surround, insets }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(LayoutID.self, forKey: .id)
    name = try c.decode(String.self, forKey: .name)
    root = try c.decode(SplitNode.self, forKey: .root)
    surround = try c.decode(Surround.self, forKey: .surround)
    insets = try c.decode(Insets.self, forKey: .insets)
    builtIn = nil
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(name, forKey: .name)
    try c.encode(root, forKey: .root)
    try c.encode(surround, forKey: .surround)
    try c.encode(insets, forKey: .insets)
  }
}
