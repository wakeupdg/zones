import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

@Suite struct WindowActorTests {
  @Test @WindowActor func timeoutsSetAtLaunch() {
    let fake = FakeWindowSystem(clock: FakeClock())
    WindowActor.applyLaunchTimeouts(to: fake)
    #expect(fake.calls == [.setTimeouts(perApp: 0.25, processWide: 1.0)])
    #expect(0.25 == Constants.perAppTimeout)
    #expect(1.0 == Constants.processTimeout)
  }
}
