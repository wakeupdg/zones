public enum LifecycleEffect: Hashable, Sendable {
  case disableTap, invalidateTap, orderPanelsOut, drainEnhancedUI, removeRecoveryRecord, revalidateTap, probe
  case forceTopologySnapshot
}
