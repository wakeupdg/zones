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
      #expect(field.isAccessibilityEnabled(), "recorder reads as dimmed to VoiceOver")
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

  @Test func valueUpdatesWithoutDraw() throws {
    let field = RecorderField(frame: NSRect(x: 0, y: 0, width: 150, height: 24))  // never displayed
    #expect(field.accessibilityValue() as? String == "Not set")
    let chord = Chord(key: .arrowRight, modifiers: [.control, .option])
    field.chord = chord
    #expect(field.accessibilityValue() as? String == ShortcutsFlow.text(for: chord))
    #expect(field.accessibilityPerformPress())
    #expect(field.accessibilityValue() as? String == "Type shortcut")
    field.chord = nil
    #expect(field.accessibilityValue() as? String == "Type shortcut")
    #expect(field.resignFirstResponder())
    #expect(field.accessibilityValue() as? String == "Not set")
  }

  /// SwiftUI exposes no in-process AX children for the row label, so the label's position is read from the
  /// rendered pixels: the vertical centre of the dark text ink left of the recorder, in the run nearest it.
  private func labelInkCentre(of hosting: NSView, beside field: RecorderField) throws -> (label: CGFloat, field: CGFloat) {
    let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    let scale = CGFloat(rep.pixelsWide) / hosting.bounds.width
    let rect = field.convert(field.bounds, to: hosting)
    let fieldTop = hosting.isFlipped ? rect.minY : hosting.bounds.height - rect.maxY
    let fieldCentre = fieldTop + rect.height / 2
    // Columns between the pane's left padding and the recorder; rows within 60 pt of the recorder.
    let x0 = Int(40 * scale)
    let x1 = Int((rect.minX - 80) * scale)
    let y0 = max(0, Int((fieldCentre - 60) * scale))
    let y1 = min(rep.pixelsHigh - 1, Int((fieldCentre + 60) * scale))
    func isInk(_ x: Int, _ y: Int) -> Bool {
      guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
      return c.redComponent < 0.5 && c.greenComponent < 0.5 && c.blueComponent < 0.5
    }
    var inkRows: [Int] = []
    for y in y0...y1 {
      let count = (x0..<x1).filter { isInk($0, y) }.count
      // Text rows have some ink; a separator or border spans nearly the whole width, so skip those.
      if count > 0 && count < (x1 - x0) / 2 { inkRows.append(y) }
    }
    var runs: [(Int, Int)] = []
    for y in inkRows {
      if let last = runs.last, y == last.1 + 1 { runs[runs.count - 1].1 = y } else { runs.append((y, y)) }
    }
    let centres = runs.map { (CGFloat($0.0 + $0.1) / 2 + 0.5) / scale }
    let nearest = try #require(centres.min { abs($0 - fieldCentre) < abs($1 - fieldCentre) })
    return (nearest, fieldCentre)
  }

  @Test func labelAndControlShareCentre() throws {
    let isolated = IsolatedDefaults()
    defer { isolated.tearDown() }
    let model = ShortcutsModel(
      preferences: PreferencesController(defaults: isolated.defaults), registrar: nil, granted: true)
    let (window, hosting) = host(model)
    defer { window.close() }
    window.appearance = NSAppearance(named: .aqua)
    spin(0.2)
    let field = try #require(recorders(in: hosting).first { $0.accessibilityLabel() == "Shortcut for Send to Zone 1" })
    let centres = try labelInkCentre(of: hosting, beside: field)
    #expect(abs(centres.label - centres.field) <= 2.5, "label centre \(centres.label) vs recorder centre \(centres.field)")
  }

  private func keyDown(_ code: UInt16, flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
      characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
  }

  /// QA-2.5: Delete and Forward Delete reach the Clear path, idle or recording.
  @Test func deleteKeysClearFromTheField() {
    for code: UInt16 in [51, 117] {
      let field = RecorderField(frame: NSRect(x: 0, y: 0, width: 150, height: 24))
      var clears = 0
      field.onClear = { clears += 1 }
      field.keyDown(with: keyDown(code))
      #expect(clears == 1)
      #expect(field.accessibilityPerformPress())
      field.keyDown(with: keyDown(code))
      #expect(clears == 2)
      #expect(!field.isRecording)
    }
  }
}
