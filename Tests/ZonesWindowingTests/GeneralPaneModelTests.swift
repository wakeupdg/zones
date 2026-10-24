import Testing
import ZonesWindowing

@Suite struct GeneralPaneModelTests {
  // AC-019
  @Test func statusRows() {
    for p in allPermissionSamples {
      for tap in allTapStates {
        let rows = GeneralPaneModel.statusRows(p, tap: tap)
        #expect(rows.count == 2)
        #expect(rows.map(\.label) == ["Accessibility", "Event tap"])
        let trusted = p == .granted || { if case .suspect = p { true } else { false } }()
        #expect(rows[0].value == (trusted ? "Granted" : "Not granted"), "\(p)")
        #expect(rows[1].value == (tap == .alive ? "Alive" : "Dead"), "\(tap)")
      }
    }
    let rows = GeneralPaneModel.statusRows(.granted, tap: .dead)
    #expect("\(rows[0].label): \(rows[0].value)" == "Accessibility: Granted")
    #expect("\(rows[1].label): \(rows[1].value)" == "Event tap: Dead")
  }
}
