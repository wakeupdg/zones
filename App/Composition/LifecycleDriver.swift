import Foundation
import ZonesCore
import ZonesWindowing

/// Wake and quit: runs the `AppLifecycle` effect lists front to back, one adapter call each (AC-026).
@MainActor
final class LifecycleDriver {
  /// Every effect run so far, in order (the order is the contract; tests read it).
  private(set) var executed: [LifecycleEffect] = []

  private let input: any InputSource
  private let probe: any PermissionProbe
  private let overlay: any OverlayPresenter
  private let recovery: EnhancedUIRecovery
  private let permission: PermissionDriver
  private let topology: TopologyDriver

  init(
    input: any InputSource, probe: any PermissionProbe, overlay: any OverlayPresenter,
    recovery: EnhancedUIRecovery, permission: PermissionDriver, topology: TopologyDriver
  ) {
    self.input = input
    self.probe = probe
    self.overlay = overlay
    self.recovery = recovery
    self.permission = permission
    self.topology = topology
  }

  func quit() {
    run(AppLifecycle.quitEffects())
    permission.cancelAllTimers()
  }

  func wake() { run(AppLifecycle.wakeEffects()) }

  func run(_ effects: [LifecycleEffect]) {
    for effect in effects {
      executed.append(effect)
      interpret(effect)
    }
  }

  private func interpret(_ effect: LifecycleEffect) {
    switch effect {
    case .disableTap: input.stop()
    // `stop()` tears the tap down (disable and invalidate in one); the effect is a marker in the sequence.
    case .invalidateTap: break
    case .orderPanelsOut: overlay.orderOut()
    case .drainEnhancedUI, .removeRecoveryRecord: recovery.drainAndDelete()
    case .revalidateTap: permission.revalidateTap()
    case .probe: permission.receive(.probe(probe.isTrusted()))
    case .forceTopologySnapshot: topology.forceSnapshot()
    }
  }
}
