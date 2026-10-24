import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

@Suite struct LoginItemToggleTests {
  static let approval = "Zones is turned off in Login Items"
  static let signed =
    "This build isn't properly signed; launch-at-login works in the signed release from /Applications"
  static let allStatuses: [LoginItemStatus] = [.enabled, .requiresApproval, .notFound, .notRegistered]

  // AC-027
  @Test func derivationTable() {
    func check(
      _ s: LoginItemStatus, _ e: LoginItemError?, on: Bool, caption: String?, button: Bool,
      sourceLocation: SourceLocation = #_sourceLocation
    ) {
      let m = LoginItemToggleModel.derive(s, error: e)
      #expect(m.isOn == on, "\(s) \(String(describing: e))", sourceLocation: sourceLocation)
      #expect(m.caption == caption, "\(s) \(String(describing: e))", sourceLocation: sourceLocation)
      #expect(m.showLoginItemsButton == button, "\(s) \(String(describing: e))", sourceLocation: sourceLocation)
      #expect(!m.disabled, "\(s) \(String(describing: e))", sourceLocation: sourceLocation)
    }
    check(.enabled, nil, on: true, caption: nil, button: false)
    check(.notRegistered, nil, on: false, caption: nil, button: false)
    check(.requiresApproval, nil, on: false, caption: Self.approval, button: true)
    check(.notFound, nil, on: false, caption: Self.approval, button: true)
    for s in Self.allStatuses {
      check(s, .launchDeniedByUser, on: s == .enabled, caption: Self.approval, button: true)
      check(s, .invalidSignature, on: s == .enabled, caption: Self.signed, button: false)
      check(s, .other("boom"), on: s == .enabled, caption: "boom", button: false)
    }
  }

  @MainActor
  @Test func registerOnlyOnUserAction() {
    let fake = FakeLoginItemService(clock: FakeClock())
    fake.enqueue(.status(.notFound))
    let coordinator = LoginItemToggleCoordinator(service: fake)
    #expect(!fake.calls.contains(.register))
    coordinator.refresh()
    #expect(!fake.calls.contains(.register))
    #expect(coordinator.model == LoginItemToggleModel.derive(.notFound, error: nil))

    // Turning on from notFound registers once, then re-reads status.
    fake.enqueue(.status(.notFound))
    coordinator.refresh()
    let before = fake.calls.count
    coordinator.setOn(true)
    let after = Array(fake.calls[before...])
    #expect(after == [.register, .status])
    #expect(coordinator.model.isOn)

    // setOn(false) unregisters.
    coordinator.setOn(false)
    #expect(fake.calls.contains(.unregister))
    #expect(!coordinator.model.isOn)
  }

  @MainActor
  @Test func invalidSignatureAndRefreshClearsError() {
    let fake = FakeLoginItemService(clock: FakeClock())
    let coordinator = LoginItemToggleCoordinator(service: fake)
    fake.enqueue(.register(.invalidSignature))
    coordinator.setOn(true)
    #expect(!coordinator.model.isOn)
    #expect(coordinator.model.caption == Self.signed)
    #expect(!coordinator.model.showLoginItemsButton)

    coordinator.refresh()
    #expect(coordinator.model.caption == nil)

    fake.enqueue(.unregister(.other("nope")))
    coordinator.setOn(false)
    #expect(coordinator.model.caption == "nope")
    coordinator.openLoginItemsSettings()
    #expect(fake.calls.last == .openLoginItemsSettings)
  }
}
