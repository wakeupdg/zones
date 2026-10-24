import Foundation
import ZonesCore

/// What the overlay lights up (LI-009: the highlight equals the drop set).
public struct Highlight: Hashable, Sendable {
  public var display: DisplayKey?
  public var primary: Set<Int>
  public var secondary: Set<Int>
  public var dimAll: Bool
  public init(display: DisplayKey?, primary: Set<Int>, secondary: Set<Int>, dimAll: Bool) {
    self.display = display
    self.primary = primary
    self.secondary = secondary
    self.dimAll = dimAll
  }
}

public struct AccessibilityOptions: Hashable, Sendable {
  public var reduceTransparency: Bool
  public var reduceMotion: Bool
  public init(reduceTransparency: Bool, reduceMotion: Bool) {
    self.reduceTransparency = reduceTransparency
    self.reduceMotion = reduceMotion
  }
}

public struct OverlayScene: Hashable, Sendable {
  public var layouts: [ResolvedLayout]
  public var appearance: Appearance
  public var options: AccessibilityOptions
  public init(layouts: [ResolvedLayout], appearance: Appearance, options: AccessibilityOptions) {
    self.layouts = layouts
    self.appearance = appearance
    self.options = options
  }
}
