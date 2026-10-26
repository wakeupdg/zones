import Testing
import ZonesLayout

@Test func hitHasThreeDistinctCases() {
  let all: Set<Hit> = [.zone(1), .nearest(1), .none]
  #expect(all.count == 3)
  #expect(Hit.zone(1) != Hit.nearest(1))
}
