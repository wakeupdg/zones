import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

@testable import Zones

@MainActor
@Suite struct LifecycleTests {
  @Test func quitAndWakeRunEffectsInOrder() {
    let h = Harness()
    h.probe.enqueue(.trusted(true))  // the wake probe still says granted
    let root = h.makeRoot()
    root.permission.receive(.probe(true))  // granted: a tap is up and the health tick is armed
    h.input.reset()
    #expect(h.clock.pending == [.healthTick])

    root.lifecycle.wake()
    #expect(root.lifecycle.executed == AppLifecycle.wakeEffects())
    #expect(h.input.calls == [.reenable])  // revalidateTap
    #expect(h.probe.calls == [.isTrusted])  // the wake probe
    #expect(h.displays.calls == [.snapshot])  // forceTopologySnapshot
    #expect(h.overlay.calls.filter { $0 == .orderOut }.count == 1)  // orderPanelsOut

    root.lifecycle.quit()
    #expect(root.lifecycle.executed == AppLifecycle.wakeEffects() + AppLifecycle.quitEffects())
    #expect(h.input.calls == [.reenable, .stop])
    #expect(h.overlay.calls.filter { $0 == .orderOut }.count == 2)
    #expect(h.files.calls.filter { if case .remove = $0 { true } else { false } }.count == 2)  // drain + record
    #expect(h.clock.pending.isEmpty)  // no timer survives quit
  }

  @Test func quitSequenceStartsWithTheTapDown() {
    let h = Harness()
    let root = h.makeRoot()
    root.lifecycle.quit()
    #expect(root.lifecycle.executed.first == .disableTap)
    #expect(root.lifecycle.executed == AppLifecycle.quitEffects())
  }
}
