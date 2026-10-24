import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

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

  // MARK: panesBuild

  private let diskKeyA = "11111111-1111-4111-8111-111111111111"  // attached (Fixtures.threeDisplays primary)
  private let diskKeyGone = "99999999-9999-4999-8999-999999999999"  // disconnected

  private func assignment(_ layout: String, name: String) -> Assignment {
    Assignment(
      layout: LayoutID(rawValue: layout), displayName: name, lastVisibleFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
      lastScale: 1, lastSeen: nil)
  }

  private func makeLayouts() -> (ImportExportController, TopologySnapshot) {
    let desk = Layout(
      id: LayoutID(rawValue: "L-desk"), name: "Desk",
      root: .split(axis: .horizontal, ratio: 0.5, first: .leaf, second: .leaf),
      surround: Surround(top: 0, left: 0, bottom: 0, right: 0), insets: Insets(margin: 3, gap: 5))
    let documents = DocumentStore(fs: FakeFileSystem(), directory: URL(fileURLWithPath: "/zones-smoke"), clock: FakeClock())
    var unstable = Fixtures.threeDisplays.displays[2]
    unstable.key = .unstable("dup:XYZ#9")
    unstable.name = "Twin"
    let topology = TopologySnapshot(
      displays: [Fixtures.threeDisplays.displays[0], unstable], separateSpaces: true,
      primaryFrame: Fixtures.threeDisplays.primaryFrame)
    let flow = LayoutsFlow(
      documents: documents, layouts: ZonesDocument(layouts: [desk]),
      assignments: [
        diskKeyA: assignment("L-desk", name: "Primary 1x"), diskKeyGone: assignment("builtin:columns:2", name: "Studio"),
      ], defaults: Insets(margin: 8, gap: 8))
    return (ImportExportController(flow: flow, fs: FakeFileSystem(), panels: .none), topology)
  }

  /// Hosts `view`, lays it out, and returns the size SwiftUI wants for it.
  private func fittingSize<V: View>(_ view: V) -> CGSize {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
    host.layoutSubtreeIfNeeded()
    return host.fittingSize
  }

  @Test func panesBuild() throws {
    let isolated = IsolatedDefaults()
    defer { isolated.tearDown() }
    let preferences = PreferencesController(defaults: isolated.defaults)
    let (layouts, topology) = makeLayouts()

    // Layouts: two attached Displays (one "not saved") and one disconnected Display.
    let rows = LayoutsPaneModel.rows(topology, assignments: layouts.flow.assignments, session: layouts.flow.session)
    #expect(rows.count == 3)
    let layoutsPane = LayoutsPane(controller: layouts, topology: { topology })
    #expect(fittingSize(layoutsPane).width > 0)
    _ = layoutsPane.body

    // Shortcuts: a conflicting chord shows a message naming the other action and stores nothing.
    let shortcuts = ShortcutsModel(preferences: preferences, registrar: nil, granted: true)
    let conflicting = Chord(key: .arrowRight, modifiers: [.control, .option])  // cycleRight's default
    shortcuts.record(conflicting, for: .restore)
    #expect(shortcuts.flow.messages[.restore]?.text.contains("Cycle right") == true)
    #expect(preferences.preferences.shortcuts == ShortcutRules.defaults)
    let shortcutsPane = ShortcutsPane(model: shortcuts)
    #expect(fittingSize(shortcutsPane).width > 0)
    _ = shortcutsPane.body

    // Exclusions: the add path stores a bundle identifier; the row shows identifier beside name (AC-142).
    let exclusions = ExclusionsModel(
      preferences: preferences,
      runningApps: { [RunningApp(name: "Safari", bundleID: "com.apple.Safari")] },
      nameForBundleID: { $0 == "com.apple.Safari" ? "Safari" : nil })
    exclusions.add(bundleID: "com.apple.Safari")
    #expect(preferences.preferences.exclusions == ["com.apple.Safari"])
    #expect(exclusions.rows == [ExclusionsPaneModel.Row(name: "Safari", bundleID: "com.apple.Safari")])
    #expect(exclusions.add(appAt: URL(fileURLWithPath: "/System/Applications/Calculator.app")))
    #expect(preferences.preferences.exclusions.contains("com.apple.calculator"))
    #expect(!exclusions.add(appAt: URL(fileURLWithPath: "/tmp/not-an-app")))
    #expect(exclusions.availableRunningApps.isEmpty)  // Safari is already excluded
    let exclusionsPane = ExclusionsPane(model: exclusions)
    #expect(fittingSize(exclusionsPane).width > 0)
    _ = exclusionsPane.body

    // Appearance: the sample lists the followers, and changes when the Margin slider changes.
    let appearance = AppearanceModel(preferences: preferences, layouts: layouts)
    let followers = AppearancePaneModel.followers(
      of: preferences.preferences.appearance.defaultInsets, in: layouts.flow.store.builtIns + layouts.flow.store.custom)
    #expect(appearance.sample.followerIDs == followers)
    #expect(!appearance.sample.customNames.contains("Desk"))  // Desk uses margin 3, gap 5
    appearance.setMargin(3)
    appearance.setGap(5)
    #expect(preferences.preferences.appearance.defaultInsets == Insets(margin: 3, gap: 5))
    #expect(appearance.sample.customNames == ["Desk"])
    #expect(appearance.sample.followerIDs != followers)
    appearance.setOpacity(0.8)
    #expect(preferences.preferences.appearance.opacity == 0.8)
    let appearancePane = AppearancePane(model: appearance)
    #expect(fittingSize(appearancePane).width > 0)
    _ = appearancePane.body
  }
}
