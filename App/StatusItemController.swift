import AppKit
import ZonesWindowing

/// Binds the menu bar icon's badge to `StatusItemModel.badged` and the menu to `MenuModel.build` output. The
/// "Grant Accessibility" item calls `onGrant` (OnboardingWindowController.grantAccessibility: opens System Settings at login, else fronts the window),
/// and "Edit Layouts…" calls `onEditLayouts` (EditorLauncher.openEditor). Items other than Grant, Edit Layouts and
/// Quit render their title only; their actions belong to the tickets that own them.
@MainActor
final class StatusItemController {
  private let statusItem: NSStatusItem
  private let onGrant: () -> Void
  private let onEditLayouts: () -> Void
  /// The red dot, a separate non-template layer over the template glyph (hidden until the model is badged).
  let badgeView = BadgeView()

  var button: NSStatusBarButton? { statusItem.button }

  init(onGrant: @escaping () -> Void, onEditLayouts: @escaping () -> Void) {
    self.onGrant = onGrant
    self.onEditLayouts = onEditLayouts
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = Self.icon(badged: false)
    installBadge()
  }

  /// Takes the item off the menu bar (tests).
  func remove() { NSStatusBar.system.removeStatusItem(statusItem) }

  private func installBadge() {
    guard let button = statusItem.button else { return }
    badgeView.isHidden = true
    badgeView.translatesAutoresizingMaskIntoConstraints = false
    button.addSubview(badgeView)
    NSLayoutConstraint.activate([
      badgeView.widthAnchor.constraint(equalToConstant: 6),
      badgeView.heightAnchor.constraint(equalToConstant: 6),
      badgeView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3),
      badgeView.topAnchor.constraint(equalTo: button.topAnchor, constant: 3),
    ])
  }

  private func render(badged: Bool) {
    statusItem.button?.image = Self.icon(badged: badged)
    badgeView.isHidden = !badged
  }

  /// Re-renders from the latest model and menu list; call on every permission or tap change.
  func apply(_ model: StatusItemModel, menu items: [MenuItem]) {
    render(badged: Self.badged(model))
    statusItem.menu = Self.makeMenu(from: items, onGrant: onGrant, onEditLayouts: onEditLayouts)
  }

  /// The live menu from `MenuController` (rebuilt on every open): the status item shows it as is.
  func attach(_ menu: NSMenu) { statusItem.menu = menu }

  /// Icon only, for callers that own the menu (the composition root's `MenuController`).
  func apply(_ model: StatusItemModel) {
    render(badged: Self.badged(model))
  }

  nonisolated static func badged(_ model: StatusItemModel) -> Bool { model.badged }

  static func makeMenu(
    from items: [MenuItem], onGrant: @escaping () -> Void, onEditLayouts: @escaping () -> Void
  ) -> NSMenu {
    let menu = NSMenu()
    for item in items {
      switch item {
      case .separator:
        menu.addItem(.separator())
      case .header(let title):
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
      case .layout(_, let title, let checked):
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        row.state = checked ? .on : .off
        menu.addItem(row)
      case .excludeApp(let name, _, let checked):
        let row = NSMenuItem(title: "Don't snap \(name)", action: nil, keyEquivalent: "")
        row.state = checked ? .on : .off
        menu.addItem(row)
      case .editLayouts:
        menu.addItem(ActionTarget.item(title: "Edit Layouts…", onEditLayouts))
      case .settings:
        menu.addItem(NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ","))
      case .grantAccessibility:
        menu.addItem(ActionTarget.item(title: "Grant Accessibility", onGrant))
      case .about:
        menu.addItem(NSMenuItem(title: "About Zones", action: nil, keyEquivalent: ""))
      case .quit:
        let quit = NSMenuItem(title: "Quit Zones", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
      }
    }
    return menu
  }

  /// The glyph as a template image in every state, so the menu bar tints it for light and dark. The badge is
  /// drawn by `badgeView`, never into this image (template tinting would erase its red).
  static func icon(badged: Bool) -> NSImage {
    let description = badged ? "Zones, needs Accessibility access" : "Zones"
    let symbol = NSImage(systemSymbolName: "rectangle.split.3x3", accessibilityDescription: description)
    let image = symbol?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) ?? symbol ?? NSImage()
    image.isTemplate = true
    image.accessibilityDescription = description
    return image
  }
}

/// A 6 pt red dot that never takes clicks or accessibility focus (the button's image carries the description).
@MainActor
final class BadgeView: NSView {
  init() {
    super.init(frame: NSRect(x: 0, y: 0, width: 6, height: 6))
    wantsLayer = true
    layer?.backgroundColor = NSColor.systemRed.cgColor
    layer?.cornerRadius = 3
    setAccessibilityElement(false)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Target for a menu item's block action.
@MainActor
final class ActionTarget: NSObject {
  private let action: () -> Void
  init(_ action: @escaping () -> Void) { self.action = action }
  @objc func fire(_ sender: Any?) { action() }

  static func item(title: String, _ action: @escaping () -> Void) -> NSMenuItem {
    let target = ActionTarget(action)
    let item = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: "")
    item.target = target
    item.representedObject = target  // keeps the target alive; NSMenuItem.target is weak
    return item
  }
}
