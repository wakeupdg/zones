import CoreGraphics
import Foundation

public enum DisplayKey: Hashable, Sendable {
  case uuid(String)
  /// Session only, never encoded.
  case unstable(String)
}

/// A display UUID that may be persisted. Encodes as a bare string; the decoder rejects non-UUID text (AC-123).
public struct PersistentDisplayKey: Hashable, Codable, Sendable {
  public let uuid: String
  public init(uuid: String) { self.uuid = uuid }

  public init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    guard UUID(uuidString: text) != nil else { throw DocumentError.nonUUIDKey(text) }
    uuid = text
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(uuid)
  }
}

public struct DisplaySnapshot: Hashable, Sendable {
  public var key: DisplayKey
  public var frame: CGRect
  public var visibleFrame: CGRect
  public var scale: Double
  public var isMain: Bool
  public var mirrorOf: DisplayKey?
  public var name: String
  public var resolution: CGSize
  public init(
    key: DisplayKey, frame: CGRect, visibleFrame: CGRect, scale: Double, isMain: Bool,
    mirrorOf: DisplayKey?, name: String, resolution: CGSize
  ) {
    self.key = key
    self.frame = frame
    self.visibleFrame = visibleFrame
    self.scale = scale
    self.isMain = isMain
    self.mirrorOf = mirrorOf
    self.name = name
    self.resolution = resolution
  }
}

public struct TopologySnapshot: Hashable, Sendable {
  public var displays: [DisplaySnapshot]
  public var separateSpaces: Bool
  public var primaryFrame: CGRect
  public init(displays: [DisplaySnapshot], separateSpaces: Bool, primaryFrame: CGRect) {
    self.displays = displays
    self.separateSpaces = separateSpaces
    self.primaryFrame = primaryFrame
  }

  public func display(_ key: DisplayKey) -> DisplaySnapshot? { displays.first { $0.key == key } }
}
