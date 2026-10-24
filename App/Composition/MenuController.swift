import AppKit
import ZonesCore
import ZonesLayout
import ZonesWindowing

/// Builds the status menu from `MenuModel.build` every time it opens (AC-016). The build reads only values the
/// main actor already holds, so opening the menu makes no Accessibility call and waits on nothing (AC-017).
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
  typealias Builder = (
    _ cursorDisplay: DisplaySnapshot?, _ assignment: LayoutID, _ store: LayoutStore,
    _ frontmost: (name: String, bundleID: String)?, _ exclusions: Set<String>, _ permission: PermissionState
  ) -> [MenuItem]

  let menu = NSMenu()
  private let appState: AppState
  private let topology: TopologyDriver
  private let permission: PermissionDriver
  private let probe: any PermissionProbe
  private let ui: UIActions
  private let frontmost: @MainActor () -> (name: String, bundleID: String)?
  private let cursor: @MainActor () -> CGPoint
  private let builder: Builder
  private var cursorDisplayKey: DisplayKey?
  private var frontmostBundleID: String?
  /// The model of the last open, for tests and for the item actions.
  private(set) var lastItems: [MenuItem] = []

  init(
    appState: AppState, topology: TopologyDriver, permission: PermissionDriver, probe: any PermissionProbe,
    ui: UIActions, frontmost: @escaping @MainActor () -> (name: String, bundleID: String)?,
    cursor: @escaping @MainActor () -> CGPoint,
    builder: @escaping Builder = {
      MenuModel.build(
        cursorDisplay: $0, assignment: $1, store: $2, frontmost: $3, exclusions: $4, permission: $5)
    }
  ) {
    self.appState = appState
    self.topology = topology
    self.permission = permission
    self.probe = probe
    self.ui = ui
    self.frontmost = frontmost
    self.cursor = cursor
    self.builder = builder
    super.init()
    menu.delegate = self
    menu.autoenablesItems = false
  }

  // MARK: NSMenuDelegate

  func menuNeedsUpdate(_ menu: NSMenu) { rebuild() }

  /// One fresh build from the current state. The cursor and the frontmost app are read now, not cached.
  @discardableResult
  func rebuild() -> [MenuItem] {
    let snapshot = topology.snapshot
    let display = snapshot.flatMap { snap in HitTest.display(at: cursor(), in: snap).flatMap { snap.display($0) } }
    cursorDisplayKey = display?.key
    let front = frontmost()
    frontmostBundleID = front?.bundleID
    let assignment = display.map { appState.assignedLayoutID(for: $0.key, session: topology.sessionAssignments) }
      ?? Templates.builtInID(.priorityGrid, count: 3)
    let items = builder(
      display, assignment, appState.layouts, front, appState.preferences.exclusions, permission.state)
    lastItems = items
    menu.removeAllItems()
    for item in items { menu.addItem(makeItem(item)) }
    return items
  }

  private func makeItem(_ item: MenuItem) -> NSMenuItem {
    switch item {
    case .separator: return .separator()
    case .header(let title):
      let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      entry.isEnabled = false
      return entry
    case .layout(let id, let title, let checked):
      let entry = NSMenuItem(title: title, action: #selector(pickLayout(_:)), keyEquivalent: "")
      entry.target = self
      entry.representedObject = id.rawValue
      entry.state = checked ? .on : .off
      entry.isEnabled = cursorDisplayKey != nil
      return entry
    case .excludeApp(let name, let bundleID, let checked):
      let entry = NSMenuItem(title: "Never Snap \(name)", action: #selector(toggleExclusion(_:)), keyEquivalent: "")
      entry.target = self
      entry.representedObject = bundleID
      entry.state = checked ? .on : .off
      return entry
    case .editLayouts: return action("Edit Layouts…", #selector(editLayouts))
    case .settings: return action("Settings…", #selector(openSettings), key: ",")
    case .grantAccessibility: return action("Grant Accessibility…", #selector(grantAccessibility))
    case .about: return action("About Zones", #selector(openAbout))
    case .quit: return action((AppDelegate.menuTitles.last ?? "Quit Zones"), #selector(quit), key: "q")
    }
  }

  private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
    let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
    entry.target = self
    return entry
  }

  // MARK: Actions

  @objc func pickLayout(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String, let key = cursorDisplayKey else { return }
    topology.pick(LayoutID(rawValue: raw), for: key)
  }

  @objc func toggleExclusion(_ sender: NSMenuItem) {
    guard let bundleID = sender.representedObject as? String else { return }
    appState.toggleExclusion(bundleID)
  }

  @objc func editLayouts() { ui.openEditor() }
  @objc func openSettings() { ui.openSettings() }
  @objc func openAbout() { ui.openAbout() }
  @objc func grantAccessibility() { probe.openAccessibilitySettings() }
  @objc func quit() { ui.requestQuit() }
}
