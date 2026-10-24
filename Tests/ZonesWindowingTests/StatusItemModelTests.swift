import Testing
import ZonesWindowing

let allPermissionSamples: [PermissionState] = [
  .notGranted, .granted, .suspect(since: 1), .revoked(failures: 3, firstFailure: 1), .needsRelaunch,
]
let allTapStates: [TapState] = [.alive, .dead, .unavailable]

@Suite struct StatusItemModelTests {
  // AC-018
  @Test func badgeTable() {
    var cases = 0
    for p in allPermissionSamples {
      for tap in allTapStates {
        let m = StatusItemModel.derive(p, tap: tap)
        #expect(m.badged == !(p == .granted && tap == .alive), "\(p) \(tap)")
        #expect(m.isTemplate)
        cases += 1
      }
    }
    #expect(cases == 15)
  }
}
