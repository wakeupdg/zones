import Testing
import ZonesWindowing

@Test func windowActorSharedIsStable() {
  #expect(WindowActor.shared === WindowActor.shared)
}
