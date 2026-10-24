/// The General pane's two read-only status rows (AC-019), always in this order.
public enum GeneralPaneModel {
  public static func statusRows(_ p: PermissionState, tap: TapState) -> [(label: String, value: String)] {
    // `suspect` is still trusted until proven otherwise (ADR-0021 amendment).
    let trusted: Bool
    switch p {
    case .granted, .suspect: trusted = true
    case .notGranted, .revoked, .needsRelaunch: trusted = false
    }
    return [
      (label: "Accessibility", value: trusted ? "Granted" : "Not granted"),
      (label: "Event tap", value: tap == .alive ? "Alive" : "Dead"),
    ]
  }
}
