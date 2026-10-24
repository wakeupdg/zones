import Foundation
import Testing
import ZonesCore

@testable import Zones

/// Fixtures for the Settings pane smoke tests: an isolated `UserDefaults` suite per test.
@MainActor
struct IsolatedDefaults {
  let suiteName = "zones.tests.\(UUID().uuidString)"
  let defaults: UserDefaults

  init() {
    defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
  }

  func tearDown() { defaults.removePersistentDomain(forName: suiteName) }
}

@MainActor
@Suite struct SettingsPanesSmokeTests {
  @Test func preferencesControllerPersists() throws {
    let isolated = IsolatedDefaults()
    defer { isolated.tearDown() }

    // An empty suite yields the defaults.
    let controller = PreferencesController(defaults: isolated.defaults)
    #expect(controller.preferences == Preferences.defaults)

    func stored() throws -> (Preferences, [String]) {
      let data = try #require(isolated.defaults.data(forKey: "zones.preferences"))
      return PreferencesCodec.decode(data)
    }

    controller.update { $0.appearance.opacity = 0.8 }
    var (decoded, coerced) = try stored()
    #expect(decoded == controller.preferences)
    #expect(coerced.isEmpty)
    #expect(decoded.appearance.opacity == 0.8)

    controller.update { $0.activationModifier = .command }
    controller.update { $0.exclusions.insert("com.apple.Safari") }
    controller.update {
      if let index = $0.shortcuts.firstIndex(where: { $0.action == .restore }) { $0.shortcuts[index].chord = nil }
    }
    (decoded, coerced) = try stored()
    #expect(decoded == controller.preferences)
    #expect(coerced.isEmpty)
    #expect(decoded.activationModifier == .command)
    #expect(decoded.exclusions == ["com.apple.Safari"])
    #expect(decoded.shortcuts.first { $0.action == .restore }?.chord == nil)

    // A fresh controller on the same suite reads the same values.
    let fresh = PreferencesController(defaults: isolated.defaults)
    #expect(fresh.preferences == controller.preferences)
  }

  @Test func equalModifiersAreCoercedByTheExistingRule() throws {
    let isolated = IsolatedDefaults()
    defer { isolated.tearDown() }
    let controller = PreferencesController(defaults: isolated.defaults)
    controller.update { $0.spanModifier = .shift }  // equals the default Activation modifier
    #expect(controller.preferences.activationModifier == .shift)
    #expect(controller.preferences.spanModifier != controller.preferences.activationModifier)
    let data = try #require(isolated.defaults.data(forKey: "zones.preferences"))
    #expect(PreferencesCodec.decode(data).0 == controller.preferences)
  }
}
