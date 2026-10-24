import AppKit
import SwiftUI
import Testing
import ZonesCore
import ZonesWindowing

@testable import Zones

/// QA-1.6 / QA-1.1: the Shortcuts pane's recorder fields are real accessibility elements and share a centre
/// line with their labels.
@MainActor
@Suite struct ShortcutsAccessibilityTests {
  /// Hosts the pane in an offscreen window tall enough that every row is realised.
  private func host(_ model: ShortcutsModel) -> (NSWindow, NSHostingView<ShortcutsPane>) {
    let hosting = NSHostingView(rootView: ShortcutsPane(model: model))
    let window = NSWindow(
      contentRect: NSRect(x: -4000, y: -4000, width: 640, height: 1600), styleMask: [.titled], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.orderFrontRegardless()
    window.layoutIfNeeded()
    spin()
    hosting.layoutSubtreeIfNeeded()
    return (window, hosting)
  }

  private func spin(_ seconds: TimeInterval = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

  private func recorders(in view: NSView) -> [RecorderField] {
    var found: [RecorderField] = []
    if let field = view as? RecorderField { found.append(field) }
    for sub in view.subviews { found += recorders(in: sub) }
    return found
  }

  @Test func recorderIsAccessibilityElement() throws {
    let isolated = IsolatedDefaults()
    defer { isolated.tearDown() }
    let preferences = PreferencesController(defaults: isolated.defaults)
    let model = ShortcutsModel(preferences: preferences, registrar: nil, granted: true)
    let (window, hosting) = host(model)
    defer { window.close() }

    let fields = recorders(in: hosting)
    #expect(fields.count == ShortcutAction.allCases.count)
    for field in fields {
      let visible = NSAccessibility.unignoredChildren(from: [field])
      #expect(visible.count == 1, "recorder is ignored by the accessibility hierarchy")
      #expect(field.accessibilityRole() == .button)
      let label = field.accessibilityLabel() ?? ""
      #expect(label.hasPrefix("Shortcut for ") && label.count > "Shortcut for ".count)
      #expect(field.accessibilityValue() as? String != nil)
    }
    // The value is the chord text, or "Not set".
    let names = ShortcutAction.allCases.map { ShortcutsFlow.name(of: $0) }
    for (action, name) in zip(ShortcutAction.allCases, names) {
      let field = try #require(fields.first { $0.accessibilityLabel() == "Shortcut for \(name)" })
      let expected = model.chord(of: action).map { ShortcutsFlow.text(for: $0) } ?? "Not set"
      #expect(field.accessibilityValue() as? String == expected)
    }
  }
}
