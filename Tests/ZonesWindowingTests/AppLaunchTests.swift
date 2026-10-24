import Testing
import ZonesWindowing

@Suite struct AppLaunchTests {
  static func config(login: Bool) -> PermissionConfig {
    PermissionConfig(launchedAtLogin: login, heartbeatEnabled: false, reducerIdle: true)
  }

  static let windowEffects: Set<PermissionEffect> = [
    .showOnboarding, .dismissOnboarding, .offerRelaunch(true), .offerRelaunch(false),
  ]

  /// Housekeeping the driver executes silently: timers, probes, the tap and hotkeys.
  static func isHousekeeping(_ e: PermissionEffect) -> Bool {
    switch e {
    case .schedule, .cancel, .probe, .heartbeat, .startTap, .registerWindowHotkeys, .unregisterWindowHotkeys:
      true
    default: false
    }
  }

  // AC-012
  @Test func loginLaunchShowsNoWindow() {
    let login = Self.config(login: true)
    let normal = Self.config(login: false)

    // (a) Trusted at login: the machine starts the tap and shows nothing.
    let (granted, grantedFx) = PermissionMachine.reduce(.notGranted, .probe(true), config: login, now: 0)
    #expect(granted == .granted)
    #expect(grantedFx.contains(.startTap))
    #expect(grantedFx.allSatisfy { !Self.windowEffects.contains($0) })
    // Granted: the status item is plain and the menu has no grant item.
    #expect(!StatusItemModel.derive(granted, tap: .alive).badged)
    #expect(!MenuModelTests.build(permission: granted).contains(.grantAccessibility))

    // (b) Not trusted at login: no window effect; the reducer emits exactly the badge and the Grant item (besides
    // housekeeping), and the state-derived models agree.
    let (denied, deniedFx) = PermissionMachine.reduce(.notGranted, .probe(false), config: login, now: 0)
    #expect(denied == .notGranted)
    #expect(deniedFx.allSatisfy { !Self.windowEffects.contains($0) })
    let nonHousekeeping = Set(deniedFx.filter { !Self.isHousekeeping($0) })
    #expect(nonHousekeeping == [.badge(true), .grantMenuItem(true)])
    #expect(StatusItemModel.derive(denied, tap: .unavailable).badged)
    #expect(MenuModelTests.build(permission: denied).contains(.grantAccessibility))

    // (c) Control: the same inputs without the login flag keep their window effects, so (a) and (b) are not vacuous.
    let (_, normalGrantedFx) = PermissionMachine.reduce(.notGranted, .probe(true), config: normal, now: 0)
    #expect(normalGrantedFx.contains(.dismissOnboarding))
    let (_, normalReonboard) = PermissionMachine.reduce(.granted, .reonboard, config: normal, now: 0)
    #expect(normalReonboard.contains(.showOnboarding))
    let (_, loginReonboard) = PermissionMachine.reduce(.granted, .reonboard, config: login, now: 0)
    #expect(!loginReonboard.contains(.showOnboarding))
  }
}
