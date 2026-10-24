import AppKit
import Foundation
import Testing
import ZonesCore
import ZonesLayout
import ZonesWindowing

@testable import Zones

@MainActor
@Suite struct EditorAccessibilityTests {
  /// Unignored accessibility elements below `element`, the way VoiceOver walks them.
  private static func unignoredElements(below element: Any) -> [Any] {
    let children = NSAccessibility.unignoredChildren(from: [element])
    var found: [Any] = []
    for child in children {
      found.append(child)
      if let object = child as? NSObject, object !== (element as? NSObject) {
        found += unignoredElements(below: object)
      }
    }
    return found
  }

  private static func text(_ any: Any?) -> String {
    switch any {
    case let string as String: return string
    case let attributed as NSAttributedString: return attributed.string
    default: return ""
    }
  }

  private static func hasName(_ element: any NSAccessibilityProtocol) -> Bool {
    if !text(element.accessibilityLabel()).isEmpty || !text(element.accessibilityTitle()).isEmpty { return true }
    return element.accessibilityTitleUIElement() != nil
  }

  private static func makeToolbar() -> (EditorToolbarView, NSWindow) {
    let toolbar = EditorToolbarView()
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 900, height: 60), styleMask: [.titled], backing: .buffered,
      defer: true)
    window.isReleasedWhenClosed = false
    window.contentView = toolbar
    toolbar.layoutSubtreeIfNeeded()
    return (toolbar, window)
  }

  @Test func toolbarControlsLabelled() {
    let (toolbar, window) = Self.makeToolbar()
    defer { window.close() }
    let elements = Self.unignoredElements(below: toolbar).compactMap { $0 as? any NSAccessibilityProtocol }
    let controls = elements.filter {
      let role = $0.accessibilityRole()
      return role == .popUpButton || role == .slider
    }
    #expect(controls.count >= 4, "expected Display, Template, Margin, Gap; saw \(controls.count)")
    for control in controls {
      #expect(Self.hasName(control), "unlabelled \(control.accessibilityRole()?.rawValue ?? "?") \(type(of: control))")
    }
  }
}
