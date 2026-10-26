/// A rectangle expressed as fractions (0...1) of a parent rectangle.
public struct UnitRect: Hashable, Codable, Sendable {
  public var x, y, width, height: Double
  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public struct RGBA: Hashable, Codable, Sendable {
  public var r, g, b, a: Double
  public init(r: Double, g: Double, b: Double, a: Double) {
    self.r = r
    self.g = g
    self.b = b
    self.a = a
  }
}
