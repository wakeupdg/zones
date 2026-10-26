import CoreGraphics
import Foundation

public struct Assignment: Hashable, Codable, Sendable {
  public var layout: LayoutID
  public var displayName: String
  public var lastVisibleFrame: CGRect
  public var lastScale: Double
  public var lastSeen: Date?

  public init(
    layout: LayoutID, displayName: String, lastVisibleFrame: CGRect, lastScale: Double, lastSeen: Date?
  ) {
    self.layout = layout
    self.displayName = displayName
    self.lastVisibleFrame = lastVisibleFrame
    self.lastScale = lastScale
    self.lastSeen = lastSeen
  }

  private enum CodingKeys: String, CodingKey {
    case layout, displayName, lastVisibleFrame, lastScale, lastSeen
  }

  /// CGRect's default Codable form is an array; the contract wants `{"x","y","width","height"}`.
  private struct FlatRect: Codable {
    var x, y, width, height: Double
    init(_ r: CGRect) {
      x = r.origin.x
      y = r.origin.y
      width = r.size.width
      height = r.size.height
    }
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    layout = try c.decode(LayoutID.self, forKey: .layout)
    displayName = try c.decode(String.self, forKey: .displayName)
    lastVisibleFrame = try c.decode(FlatRect.self, forKey: .lastVisibleFrame).rect
    lastScale = try c.decode(Double.self, forKey: .lastScale)
    if let text = try c.decodeIfPresent(String.self, forKey: .lastSeen) {
      guard let date = Self.parseDate(text) else {
        throw DecodingError.dataCorruptedError(
          forKey: .lastSeen, in: c, debugDescription: "lastSeen is not an ISO-8601 date")
      }
      lastSeen = date
    } else {
      lastSeen = nil
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(layout, forKey: .layout)
    try c.encode(displayName, forKey: .displayName)
    try c.encode(FlatRect(lastVisibleFrame), forKey: .lastVisibleFrame)
    try c.encode(lastScale, forKey: .lastScale)
    if let lastSeen {
      try c.encode(ISO8601DateFormatter().string(from: lastSeen), forKey: .lastSeen)
    }
  }

  private static func parseDate(_ text: String) -> Date? {
    if let date = ISO8601DateFormatter().date(from: text) { return date }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: text)
  }
}
