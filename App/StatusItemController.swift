import AppKit
import ZonesWindowing

/// Binds the menu bar icon's badge to `StatusItemModel.badged` and the menu to `MenuModel.build` output. The
/// "Grant Accessibility" item calls `onGrant` (OnboardingWindowController.show). Items other than Grant and Quit
/// render their title only; their actions belong to the tickets that own them.
@MainActor
final class StatusItemController {
  private let statusItem: NSStatusItem
  private let onGrant: () -> Void

  init(onGrant: @escaping () -> Void) {
    self.onGrant = onGrant
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = Self.icon(badged: false)
  }

  /// Re-renders from the latest model and menu list; call on every permission or tap change.
  func apply(_ model: StatusItemModel, menu items: [MenuItem]) {
    statusItem.button?.image = Self.icon(badged: Self.badged(model))
    statusItem.menu = Self.makeMenu(from: items, onGrant: onGrant)
  }

  nonisolated static func badged(_ model: StatusItemModel) -> Bool { model.badged }

  static func makeMenu(from items: [MenuItem], onGrant: @escaping () -> Void) -> NSMenu {
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
        menu.addItem(NSMenuItem(title: "Edit Layouts…", action: nil, keyEquivalent: ""))
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

  /// A template-style glyph drawn in `labelColor` (so it tints for light and dark menu bars) with a red dot when
  /// badged.
  static func icon(badged: Bool) -> NSImage {
    let base = NSImage(systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "Zones")
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
      if let base {
        let tinted = base.withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) ?? base
        tinted.isTemplate = true
        let glyph = NSRect(x: 1, y: 1, width: 16, height: 16)
        NSColor.labelColor.set()
        tinted.draw(in: glyph, from: .zero, operation: .sourceOver, fraction: 1)
        // Recolour the template glyph with the label colour.
        glyph.fill(using: .sourceIn)
      }
      if badged {
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.maxX - 7, y: rect.maxY - 7, width: 6, height: 6)).fill()
      }
      return true
    }
    image.isTemplate = false
    image.accessibilityDescription = badged ? "Zones, needs Accessibility access" : "Zones"
    return image
  }
}

/// Target for a menu item's block action.
@MainActor
private final class ActionTarget: NSObject {
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
