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

  /// An invalid command's message is spoken: VoiceOver ignores value changes of an unfocused static text
  /// (QA-2.4), so `show(message:)` must post `.announcementRequested` with the text, and nothing for "".
  @Test func messagesAreAnnounced() throws {
    let (toolbar, window) = Self.makeToolbar()
    defer { window.close() }
    var announced: [String] = []
    toolbar.postAnnouncement = { _, message in announced.append(message) }

    // A fresh one-Zone Layout with its Zone selected: Merge is refused with the reducer's error.
    let topology = EditorWindowTests.topology()
    let layout = EditorWindowTests.blankLayout()
    var state = EditorModel.open(
      layout, display: .uuid("AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"), topology: topology, assignments: [:])
    let context = (topology: topology, document: ZonesDocument())
    (state, _) = EditorModel.reduce(state, .command(.select(NodePath(steps: []))), context: context)
    let (_, effects) = EditorModel.reduce(state, .command(.merge), context: context)
    let error: EditorError = try #require(
      effects.compactMap { effect -> EditorError? in
        if case .error(let error) = effect { return error }
        return nil
      }.first)
    let text = EditorEffectRouter.text(for: error)
    #expect(!text.isEmpty)

    toolbar.show(message: text)
    #expect(announced == [text])

    toolbar.show(message: "")
    #expect(announced == [text], "an empty message is cleared silently")
  }
}
