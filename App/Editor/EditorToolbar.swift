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

/// The editor's floating control bar: Display switcher, Template picker, Margin and Gap sliders, Assign, Save, Save
/// and Close, and an inline message. All decisions come from `EditorToolbarModel` and the reducer.
@MainActor
final class EditorToolbarView: NSVisualEffectView {
  var onEvent: (EditorEvent) -> Void = { _ in }
  var onSaveAndClose: () -> Void = {}

  private let displayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let templatePopup = NSPopUpButton(frame: .zero, pullsDown: true)
  private let marginSlider = NSSlider()
  private let gapSlider = NSSlider()
  private let marginLabel = NSTextField(labelWithString: "Margin 0")
  private let gapLabel = NSTextField(labelWithString: "Gap 0")
  private let messageLabel = NSTextField(labelWithString: "")
  private var choices: [EditorToolbarModel.DisplayChoice] = []
  private var currentDisplay: DisplayKey?
  private var margin = 0.0
  private var gap = 0.0

  init() {
    super.init(frame: .zero)
    material = .hudWindow
    blendingMode = .withinWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.masksToBounds = true

    displayPopup.target = self
    displayPopup.action = #selector(displayPicked)
    displayPopup.setAccessibilityLabel("Display")

    templatePopup.addItem(withTitle: "Template")
    for (index, choice) in EditorToolbarModel.templateChoices.enumerated() {
      templatePopup.addItem(withTitle: choice.title)
      templatePopup.lastItem?.tag = index
    }
    templatePopup.target = self
    templatePopup.action = #selector(templatePicked)
    templatePopup.setAccessibilityLabel("Template")

    for slider in [marginSlider, gapSlider] {
      slider.minValue = EditorToolbarModel.insetRange.lowerBound
      slider.maxValue = EditorToolbarModel.insetRange.upperBound
      slider.isContinuous = true
      slider.target = self
      slider.widthAnchor.constraint(equalToConstant: 90).isActive = true
    }
    marginSlider.action = #selector(marginMoved)
    gapSlider.action = #selector(gapMoved)
    marginSlider.setAccessibilityLabel("Margin")
    gapSlider.setAccessibilityLabel("Gap")

    let assign = NSButton(title: "Assign", target: self, action: #selector(assignPressed))
    let save = NSButton(title: "Save", target: self, action: #selector(savePressed))
    let saveClose = NSButton(title: "Save and Close", target: self, action: #selector(saveClosePressed))
    messageLabel.textColor = .systemRed
    messageLabel.lineBreakMode = .byTruncatingTail
    messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let row = NSStackView(views: [
      displayPopup, templatePopup, marginLabel, marginSlider, gapLabel, gapSlider, assign, save, saveClose,
      messageLabel,
    ])
    row.orientation = .horizontal
    row.spacing = 10
    row.alignment = .centerY
    row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
      row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  @available(*, unavailable) required init?(coder: NSCoder) { nil }

  /// Refreshes every control from the state; setting a control's value does not fire its action.
  func update(state: EditorState, topology: TopologySnapshot, assignments: [String: Assignment]) {
    choices = EditorToolbarModel.displayChoices(topology: topology, assignments: assignments)
    if !choices.contains(where: { $0.key == state.display }) {
      choices.append(.init(key: state.display, name: "Unknown Display", isConnected: false))
    }
    currentDisplay = state.display
    displayPopup.removeAllItems()
    for choice in choices {
      displayPopup.addItem(withTitle: choice.isConnected ? choice.name : "\(choice.name) (disconnected)")
    }
    if let index = choices.firstIndex(where: { $0.key == state.display }) { displayPopup.selectItem(at: index) }
    margin = state.draft.layout.insets.margin
    gap = state.draft.layout.insets.gap
    marginSlider.doubleValue = margin
    gapSlider.doubleValue = gap
    marginLabel.stringValue = "Margin \(Int(margin.rounded()))"
    gapLabel.stringValue = "Gap \(Int(gap.rounded()))"
  }

  func show(message: String) { messageLabel.stringValue = message }

  @objc private func displayPicked() {
    let index = displayPopup.indexOfSelectedItem
    guard choices.indices.contains(index), choices[index].key != currentDisplay else { return }
    let key = choices[index].key
    // Put the popup back until the reducer confirms the switch; a refused switch must not leave it on the target.
    if let current = choices.firstIndex(where: { $0.key == currentDisplay }) { displayPopup.selectItem(at: current) }
    onEvent(EditorToolbarModel.pickDisplay(key))
  }

  @objc private func templatePicked() {
    let index = templatePopup.selectedItem?.tag ?? -1
    guard EditorToolbarModel.templateChoices.indices.contains(index) else { return }
    onEvent(EditorToolbarModel.templateEvent(EditorToolbarModel.templateChoices[index]))
  }

  @objc private func marginMoved() {
    let event = EditorToolbarModel.marginEvent(sliderValue: marginSlider.doubleValue)
    guard case .command(.setMargin(let value)) = event, value != margin.rounded() else { return }
    onEvent(event)
  }

  @objc private func gapMoved() {
    let event = EditorToolbarModel.gapEvent(sliderValue: gapSlider.doubleValue)
    guard case .command(.setGap(let value)) = event, value != gap.rounded() else { return }
    onEvent(event)
  }

  @objc private func assignPressed() { onEvent(.assign) }
  @objc private func savePressed() { onEvent(.save) }
  @objc private func saveClosePressed() { onSaveAndClose() }
}
