import AppKit
import Testing
import ZonesCore
import ZonesLayout
import ZonesWindowing

@testable import Zones

@MainActor
@Suite struct OverlayPanelTests {
  static let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

  @Test func configuration() {
    let panel = ZoneOverlayPanel(screenFrame: Self.screen)
    #expect(panel.ignoresMouseEvents)
    #expect(!panel.canBecomeKey)
    #expect(!panel.canBecomeMain)
    #expect(panel.level == .screenSaver)
    #expect(!panel.hasShadow)
    #expect(panel.backgroundColor == .clear)
    #expect(!panel.isOpaque)
    for behavior: NSWindow.CollectionBehavior in [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle] {
      #expect(panel.collectionBehavior.contains(behavior))
    }
    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.styleMask.contains(.borderless))
    #expect(panel.frame == Self.screen)
  }
}
