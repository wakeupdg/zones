import ZonesCore
import ZonesLayout

public enum MenuItem: Hashable, Sendable {
  case header(String)
  case layout(LayoutID, title: String, checked: Bool)
  case excludeApp(name: String, bundleID: String, checked: Bool)
  case editLayouts, settings, grantAccessibility, about, quit, separator
}

/// The status item menu as a value list (AC-016). A plain synchronous pure function over its arguments: it takes
/// already-captured snapshots, so building it never waits on anything else (AC-017).
public enum MenuModel {
  public static func build(
    cursorDisplay: DisplaySnapshot?, assignment: LayoutID, store: LayoutStore,
    frontmost: (name: String, bundleID: String)?, exclusions: Set<String>, permission: PermissionState
  ) -> [MenuItem] {
    let layouts = store.builtIns + store.custom
    let assigned = store.layout(assignment).map(title) ?? assignment.rawValue
    let header = cursorDisplay.map { "\($0.name) — \(assigned)" } ?? "No display"

    var items: [MenuItem] = [.header(header), .separator]
    items += layouts.map { .layout($0.id, title: title($0), checked: cursorDisplay != nil && $0.id == assignment) }
    items.append(.separator)
    if let frontmost {
      items.append(
        .excludeApp(
          name: frontmost.name, bundleID: frontmost.bundleID, checked: exclusions.contains(frontmost.bundleID)))
      items.append(.separator)
    }
    items += [.editLayouts, .settings]
    if showsGrant(permission) { items.append(.grantAccessibility) }
    items += [.separator, .about, .quit]
    return items
  }

  /// Built-ins read "<Template> <count>"; custom Layouts use their own name.
  private static func title(_ l: Layout) -> String {
    if let ref = l.builtIn { return "\(ref.template.rawValue) \(ref.count)" }
    return l.name
  }

  /// Mirrors the reducer's `grantMenuItem`: `suspect` is still trusted until proven otherwise.
  private static func showsGrant(_ p: PermissionState) -> Bool {
    switch p {
    case .granted, .suspect: false
    case .notGranted, .revoked, .needsRelaunch: true
    }
  }
}
