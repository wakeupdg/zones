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

  @Test func launchSequenceOrder() async {
    let h = Harness()
    h.probe.enqueue(.trusted(true))
    let root = h.makeRoot()
    await root.start()
    #expect(root.launchTrace == ["timeouts", "enhancedUIRecovery", "permissionProbe"])
    #expect(h.windows.calls.first == .setTimeouts(perApp: Constants.perAppTimeout, processWide: Constants.processTimeout))
    #expect(h.probe.calls == [.isTrusted])
    #expect(h.input.calls == [.start])
    #expect(root.permission.state == .granted)
    // Granted: only the 5 s health tick is pending (AC-157).
    #expect(h.clock.pending == [.healthTick])
  }

  @Test func tapStaysDownWhileNotGranted() async {
    let h = Harness()
    h.probe.enqueue(.trusted(false))
    let root = h.makeRoot()
    await root.start()
    #expect(h.input.calls.isEmpty)
    #expect(root.permission.state == .notGranted)
    #expect(h.clock.pending == [.trustPoll])
    #expect(h.surfaces.calls == [.showOnboarding])
  }

  @Test func enhancedUIRecoveredBeforeProbe() async {
    let h = Harness()
    let launch = Date(timeIntervalSince1970: 1_000)
    let record = RecoveryRecord(bundleID: "com.example.app", pid: 4242, launchDate: launch, priorEnhancedUI: true)
    let store = DocumentStore(fs: h.files, directory: URL(filePath: "/zones-support"), clock: h.clock)
    EnhancedUIRecovery(store: store).noteIfFirst(record)
    h.running.withLock { $0 = [record] }
    h.probe.enqueue(.trusted(true))
    let root = h.makeRoot()
    await root.start()
    #expect(h.windows.calls.contains(.setEnhancedUI(true, 4242)))
    let recovered = h.windows.calls.firstIndex(of: .setEnhancedUI(true, 4242))
    let timeouts = h.windows.calls.firstIndex(of: .setTimeouts(perApp: Constants.perAppTimeout, processWide: Constants.processTimeout))
    #expect(timeouts != nil && recovered != nil && timeouts! < recovered!)
  }
}
