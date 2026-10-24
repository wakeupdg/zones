import AppKit
import Testing
import ZonesCore
import ZonesLayout
import ZonesWindowing

@testable import Zones

/// Slice 8: the badge follows `StatusItemModel.badged` and the "Grant Accessibility" item (from
/// `MenuModel.build`) calls the onboarding `show`. The model and menu content themselves are pinned in
/// StatusItemModelTests and MenuModelTests; this covers only the controller binding.
@MainActor
@Suite struct StatusItemBindingTests {
  @Test func grantItemRendersAndCallsShow() throws {
    var shown = 0
    let menu = StatusItemController.makeMenu(
      from: [.header("Display"), .separator, .settings, .grantAccessibility, .separator, .quit],
      onGrant: { shown += 1 })
    let item = try #require(menu.items.first { $0.title == "Grant Accessibility" })
    _ = item.target?.perform(item.action, with: item)
    #expect(shown == 1)
    #expect(menu.items.last?.title == "Quit Zones")
  }

  @Test func badgeFollowsModel() {
    #expect(StatusItemController.badged(StatusItemModel.derive(.revoked(failures: 3, firstFailure: 0), tap: .dead)))
    #expect(!StatusItemController.badged(StatusItemModel.derive(.granted, tap: .alive)))
  }
}
