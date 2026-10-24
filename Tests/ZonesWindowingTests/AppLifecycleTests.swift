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

  @Test func wakeEffectsOrder() {
    #expect(AppLifecycle.wakeEffects() == [.revalidateTap, .probe, .forceTopologySnapshot, .orderPanelsOut])
  }

  /// The machine's `.quit` only emits `disableTap` from the quit list (the rest is driver work after the timers are
  /// cancelled). What it does emit must appear in `quitEffects()` in the same relative order, so the two never
  /// contradict each other.
  @Test func quitMatchesPermissionMachine() {
    let config = PermissionConfig(launchedAtLogin: false, heartbeatEnabled: false, reducerIdle: true)
    let (_, fx) = PermissionMachine.reduce(.granted, .quit, config: config, now: 0)
    let mapped: [LifecycleEffect] = fx.compactMap {
      switch $0 {
      case .disableTap: .disableTap
      case .invalidateTap: .invalidateTap
      case .orderPanelsOut: .orderPanelsOut
      case .drainEnhancedUI: .drainEnhancedUI
      case .removeRecoveryRecord: .removeRecoveryRecord
      default: nil
      }
    }
    #expect(!mapped.isEmpty)
    var rest = AppLifecycle.quitEffects()[...]
    for effect in mapped {
      let index = rest.firstIndex(of: effect)
      #expect(index != nil)
      if let index { rest = rest[(index + 1)...] }
    }
  }
}
