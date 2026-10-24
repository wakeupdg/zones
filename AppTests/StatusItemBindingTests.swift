import AppKit
import Testing
import ZonesCore
import ZonesLayout
import ZonesWindowing

@testable import Zones

/// Slice 8: the badge follows `StatusItemModel.badged` and the "Grant Accessibility" item (from
/// `MenuModel.build`) calls `onGrant` (OnboardingWindowController.grantAccessibility). The model and menu content themselves are pinned in
/// StatusItemModelTests and MenuModelTests; this covers only the controller binding.
@MainActor
@Suite struct StatusItemBindingTests {
  @Test func grantItemRendersAndCallsShow() throws {
    var shown = 0
    let menu = StatusItemController.makeMenu(
      from: [.header("Display"), .separator, .settings, .grantAccessibility, .separator, .quit],
      onGrant: { shown += 1 }, onEditLayouts: {})
    let item = try #require(menu.items.first { $0.title == "Grant Accessibility" })
    _ = item.target?.perform(item.action, with: item)
    #expect(shown == 1)
    #expect(menu.items.last?.title == "Quit Zones")
  }

  @Test func badgeFollowsModel() {
    #expect(StatusItemController.badged(StatusItemModel.derive(.revoked(failures: 3, firstFailure: 0), tap: .dead)))
    #expect(!StatusItemController.badged(StatusItemModel.derive(.granted, tap: .alive)))
  }

  /// QA-1.9 / AC-018: the glyph is a template image in every state; the red badge is a separate non-template
  /// subview shown only when the model is badged.
  @Test func imageIsTemplateInEveryState() throws {
    let controller = StatusItemController(onGrant: {}, onEditLayouts: {})
    defer { controller.remove() }
    let button = try #require(controller.button)
    #expect(button.image?.isTemplate == true)
    #expect(controller.badgeView.isHidden)
    for badged in [true, false, true] {
      controller.apply(StatusItemModel(badged: badged))
      #expect(button.image?.isTemplate == true)
      #expect(controller.badgeView.superview === button)
      #expect(controller.badgeView.isHidden == !badged)
      #expect(button.image?.accessibilityDescription == (badged ? "Zones, needs Accessibility access" : "Zones"))
    }
  }
}
