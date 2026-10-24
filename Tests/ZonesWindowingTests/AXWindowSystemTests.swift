import Testing
import ZonesCore

@testable import ZonesWindowing

@Suite struct AXWindowSystemTests {
  @Test @WindowActor func conformsAndTimeoutsDoNotCrash() {
    let system: any WindowSystem = AXWindowSystem()
    system.setTimeouts(perApp: Constants.perAppTimeout, processWide: Constants.processTimeout)
    let status = system.trivialRead()
    // CI may run untrusted, so any of these is acceptable; the call must not crash or hang.
    switch status {
    case .ok, .apiDisabled, .timedOut: break
    case .elementGone, .refused: Issue.record("unexpected trivialRead result \(status)")
    }
  }
}
