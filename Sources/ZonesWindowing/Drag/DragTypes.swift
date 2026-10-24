import CoreGraphics
import Foundation
import ZonesCore
import ZonesLayout

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

/// Read at mouse-down only (AC-111).
public struct ModifierConfig: Hashable, Sendable {
  public var activation: Modifier
  public var span: Modifier
  public init(activation: Modifier, span: Modifier) {
    self.activation = activation
    self.span = span
  }
}

public struct SpanState: Hashable, Sendable {
  public var zones: Set<Int>
  public var display: DisplayKey?
  public var frozen: Bool
  public var suspended: Bool
  public init(zones: Set<Int>, display: DisplayKey?, frozen: Bool, suspended: Bool) {
    self.zones = zones
    self.display = display
    self.frozen = frozen
    self.suspended = suspended
  }
}

public enum SampleResult: Hashable, Sendable { case frame(CGRect, WindowFacts?), timedOut, gone }

public struct ArmContext: Hashable, Sendable {
  public var topology: TopologySnapshot
  public var layouts: [DisplayKey: ResolvedLayout]
  public var appearance: Appearance
  public var options: AccessibilityOptions
  public var hasOriginalFrame: Bool
  public init(
    topology: TopologySnapshot, layouts: [DisplayKey: ResolvedLayout], appearance: Appearance,
    options: AccessibilityOptions, hasOriginalFrame: Bool
  ) {
    self.topology = topology
    self.layouts = layouts
    self.appearance = appearance
    self.options = options
    self.hasOriginalFrame = hasOriginalFrame
  }
}

public enum DragState: Hashable, Sendable {
  case idle
  case pressed(
    candidates: [WindowRef], down: CGPoint, downFrames: [WindowID: CGRect], flags: ModifierSet,
    config: ModifierConfig, samples: Int, retried: Bool)
  case moving(window: WindowRef, downFrame: CGRect, flags: ModifierSet, config: ModifierConfig)
  case armed(
    window: WindowRef, downFrame: CGRect, flags: ModifierSet, config: ModifierConfig,
    context: ArmContext, display: DisplayKey?, hit: Hit, span: SpanState, point: CGPoint?)
}

public enum DragEvent: Hashable, Sendable {
  case mouseDown(
    point: CGPoint, flags: ModifierSet, candidates: [WindowRef], phaseOne: Verdict,
    config: ModifierConfig)
  case dragged(point: CGPoint, flags: ModifierSet)
  case mouseUp(point: CGPoint, flags: ModifierSet)
  case flagsChanged(ModifierSet)
  /// One batched read per tick; facts ride with the first moved sample.
  case frameSample([WindowID: SampleResult])
  /// The driver answers `requestArmContext`.
  case armContext(ArmContext)
  case windowGone
  case topologyChanged(ArmContext)
  case spaceChanged
  case wake
}

public enum DragEffect: Hashable, Sendable {
  case requestSample([WindowID])
  case stopSampling
  case requestArmContext(window: WindowRef, point: CGPoint)
  case showOverlay(OverlayScene)
  case updateHighlight(Highlight)
  case hideOverlay
  case reassertPanels
  case snap(SnapPlan)
  case restore(WindowRef, downFrame: CGRect)
  case skip(SkipReason, WindowRef?)
  case log(String)
}
