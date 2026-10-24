import AppKit
import ZonesCore
import ZonesLayout

/// Pure model behind the toolbar controls. Everything the controls decide lives here so AppTests can reach it
/// without AppKit; the reducer still owns every editing rule.
enum EditorToolbarModel {
  struct DisplayChoice: Hashable {
    var key: DisplayKey
    var name: String
    var isConnected: Bool
  }

  /// Connected Displays first (topology order), then disconnected ones known only from Assignment records
  /// (ADR-0012), by stored `displayName` then UUID so the order is stable.
  static func displayChoices(topology: TopologySnapshot, assignments: [String: Assignment]) -> [DisplayChoice] {
    let connected = topology.displays.map { DisplayChoice(key: $0.key, name: $0.name, isConnected: true) }
    let disconnected = assignments
      .filter { topology.display(.uuid($0.key)) == nil }
      .sorted { ($0.value.displayName, $0.key) < ($1.value.displayName, $1.key) }
      .map { DisplayChoice(key: .uuid($0.key), name: $0.value.displayName, isConnected: false) }
    return connected + disconnected
  }

  /// Picking a Display. A dirty draft answers `promptUnsaved` from the reducer; nothing is switched yet.
  static func pickDisplay(_ key: DisplayKey) -> EditorEvent { .switchDisplay(key, confirmed: false) }

  /// The user confirmed the unsaved-changes prompt: switch and keep the draft.
  static func confirmSwitch(to key: DisplayKey) -> EditorEvent { .switchDisplay(key, confirmed: true) }

  /// Slider range in points. The reducer accepts any finite value >= 0 (it has no upper bound), so this is the
  /// UI's own bound; values are whole points.
  static let insetRange: ClosedRange<Double> = 0...64

  static func marginEvent(sliderValue: Double) -> EditorEvent { .command(.setMargin(clamped(sliderValue))) }
  static func gapEvent(sliderValue: Double) -> EditorEvent { .command(.setGap(clamped(sliderValue))) }

  /// Whole points inside `insetRange`; NaN becomes the lower bound.
  private static func clamped(_ value: Double) -> Double {
    guard !value.isNaN else { return insetRange.lowerBound }
    return min(max(value.rounded(), insetRange.lowerBound), insetRange.upperBound)
  }

  /// One picker row: a Template and its zone count, as in "Columns 3".
  struct TemplateChoice: Hashable {
    var template: Template
    var count: Int
    var title: String { "\(template.rawValue) \(count)" }
  }

  /// Every Template with each of its counts, in `Template.allCases` order.
  static let templateChoices: [TemplateChoice] = Template.allCases.flatMap { template in
    template.counts.map { TemplateChoice(template: template, count: $0) }
  }

  static func templateEvent(_ choice: TemplateChoice) -> EditorEvent {
    .command(.template(choice.template, count: choice.count))
  }
}
