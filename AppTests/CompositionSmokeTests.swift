import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

@testable import Zones

@MainActor
@Suite struct CompositionSmokeTests {
  @Test func rootBuildsWithFakes() {
    let h = Harness()
    let root = h.makeRoot()
    #expect(root.state.preferences == Preferences.defaults)
    // Construction touches no adapter and leaves no timer behind (AC-157 idle path).
    #expect(h.clock.pending.isEmpty)
    #expect(h.windows.calls.isEmpty)
    #expect(h.input.calls.isEmpty)
    #expect(h.enumerator.calls.isEmpty)
    #expect(h.displays.calls.isEmpty)
    #expect(h.overlay.calls.isEmpty)
    #expect(h.hotkeys.calls.isEmpty)
    #expect(h.probe.calls.isEmpty)
  }
}
