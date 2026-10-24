import ZonesCore

/// ADR-0015: every Accessibility call runs on this actor; UI runs on the main actor.
@globalActor public actor WindowActor {
  public static let shared = WindowActor()

  /// Applies the 250 ms per-app and 1 s process-wide messaging timeouts (AC-159). Call once at launch.
  @WindowActor public static func applyLaunchTimeouts(to system: any WindowSystem) {
    system.setTimeouts(perApp: Constants.perAppTimeout, processWide: Constants.processTimeout)
  }
}
