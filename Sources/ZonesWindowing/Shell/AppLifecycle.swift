/// App-level lifecycle sequences as ordered value lists (AC-026). The order is the contract: the driver executes the
/// effects front to back.
public enum AppLifecycle {
  /// Quit: stop the tap first, drop it, hide panels, restore Enhanced UI, then forget the recovery record.
  public static func quitEffects() -> [LifecycleEffect] {
    [.disableTap, .invalidateTap, .orderPanelsOut, .drainEnhancedUI, .removeRecoveryRecord]
  }

  /// Wake from sleep: re-validate the tap, probe permission, rebuild the topology, hide stale panels.
  public static func wakeEffects() -> [LifecycleEffect] {
    [.revalidateTap, .probe, .forceTopologySnapshot, .orderPanelsOut]
  }
}
