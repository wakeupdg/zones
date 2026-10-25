import AppKit
import ApplicationServices
import SwiftUI
import Testing
import ZonesCore
import ZonesWindowing

@testable import Zones

/// QA-1.0: an inapplicable Back or Next is disabled, not dimmed while still enabled.
@MainActor
@Suite struct OnboardingViewTests {
  private func makeModel() -> OnboardingModel {
    OnboardingModel(preferences: Preferences.defaults, openSettings: {}, quitAndReopen: {})
  }

  @Test func inapplicableNavIsDisabled() {
    let model = makeModel()
    model.page = .accessibility
    #expect(!model.canGoBack)
    #expect(model.canGoNext)
    model.page = .cheatSheet
    #expect(model.canGoBack)
    #expect(!model.canGoNext)
  }

  /// What VoiceOver speaks for each element reachable from `root` through `accessibilityChildren()`: the label,
  /// or for a static text (whose label SwiftUI reports as the value) the value. The hosted nodes are
  /// `AccessibilityNode` objects that answer the selectors but do not cast to `NSAccessibilityProtocol`.
  private func spoken(under root: Any, depth: Int = 0) -> [String] {
    guard depth < 40, let node = root as? NSObject else { return [] }
    func read(_ selector: Selector) -> Any? {
      node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() : nil
    }
    var found: [String] = []
    if let label = read(#selector(NSAccessibilityProtocol.accessibilityLabel)) as? String, !label.isEmpty {
      found.append(label)
    } else if read(#selector(NSAccessibilityProtocol.accessibilityRole)) as? String
      == NSAccessibility.Role.staticText.rawValue,
      let value = read(#selector(NSAccessibilityProtocol.accessibilityValue)) as? String
    {
      found.append(value)
    }
    for child in (read(#selector(NSAccessibilityProtocol.accessibilityChildren)) as? [Any]) ?? [] {
      found += spoken(under: child, depth: depth + 1)
    }
    return found
  }

  /// T56: VoiceOver reads the stale-entry help line once it shows (it speaks exactly the sentence), and not before.
  @Test func staleEntryHelpIsReadByVoiceOver() {
    let model = makeModel()
    model.permission = .notGranted
    let hosting = NSHostingView(rootView: OnboardingView(model: model))
    let window = NSWindow(
      contentRect: NSRect(x: -4000, y: -4000, width: 480, height: 360), styleMask: [.titled], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.orderFrontRegardless()
    defer { window.close() }
    let sentence = OnboardingViewState.staleEntrySentence

    wakeAccessibility()
    let before = spoken(under: hosting)
    #expect(before.contains("Next"), "the walk must see the hosted SwiftUI tree; saw \(before)")
    #expect(before.contains("Waiting for Accessibility access"), "static text must be read; saw \(before)")
    #expect(!before.contains(sentence))
    model.waited = 10
    wakeAccessibility()
    #expect(spoken(under: hosting).contains(sentence))
  }

  /// SwiftUI builds a hosting view's accessibility tree only once an AX client asks: one read of this process's
  /// windows through the AX API (no trust needed for our own pid) makes `accessibilityChildren()` non-empty.
  private func wakeAccessibility() {
    spin()
    var windows: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(getpid()), kAXWindowsAttribute as CFString, &windows)
    spin()
  }

  private func spin(_ seconds: TimeInterval = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
}
