import AppKit
import Testing
import ZonesCore
import ZonesLayout
import ZonesWindowing

@testable import Zones

@MainActor
@Suite struct EditorWindowTests {
  static func display(
    key: String = "D1", frame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900),
    visible: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 875)
  ) -> DisplaySnapshot {
    DisplaySnapshot(
      key: .uuid(key), frame: frame, visibleFrame: visible, scale: 2, isMain: true, mirrorOf: nil,
      name: "Built-in", resolution: CGSize(width: 2880, height: 1800))
  }

  @Test func defaultFrameEqualsVisibleFrame() {
    let snapshot = Self.display()  // visibleFrame is inset by a 25 pt menu bar
    let window = EditorWindowController.makeWindow(display: snapshot)
    #expect(window.frame == WindowPlacement.editorFrame(cursor: snapshot))
    #expect(window.frame == snapshot.visibleFrame)
    #expect(window.styleMask.contains(.resizable))
    #expect(!window.isOpaque)
  }
}
