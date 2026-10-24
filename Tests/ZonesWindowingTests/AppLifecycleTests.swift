import Testing
import ZonesCore
import ZonesWindowing

@Suite struct AppLifecycleTests {
  // AC-026
  @Test func quitEffectsInOrder() {
    #expect(
      AppLifecycle.quitEffects()
        == [.disableTap, .invalidateTap, .orderPanelsOut, .drainEnhancedUI, .removeRecoveryRecord])
  }
}
