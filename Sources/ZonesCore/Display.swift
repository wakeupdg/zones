import CoreGraphics
import Foundation

public enum DisplayKey: Hashable, Sendable {
  case uuid(String)
  /// Session only, never encoded.
  case unstable(String)
}

/// A display UUID that may be persisted. Decoder validation (AC-123) belongs to the persistence ticket.
public struct PersistentDisplayKey: Hashable, Codable, Sendable {
  public let uuid: String
  public init(uuid: String) { self.uuid = uuid }
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
  // `display(_:)` is added by the topology ticket.
  public init(displays: [DisplaySnapshot], separateSpaces: Bool, primaryFrame: CGRect) {
    self.displays = displays
    self.separateSpaces = separateSpaces
    self.primaryFrame = primaryFrame
  }
}
