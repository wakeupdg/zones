import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import ZonesCore
import ZonesWindowing

/// A running regular app that can be excluded.
struct RunningApp: Hashable {
  var name: String
  var bundleID: String

  /// Regular apps (Dock-visible) with a bundle identifier, sorted by name.
  @MainActor
  static func current() -> [RunningApp] {
    NSWorkspace.shared.runningApplications
      .compactMap { app -> RunningApp? in
        guard app.activationPolicy == .regular, let id = app.bundleIdentifier, let name = app.localizedName else {
          return nil
        }
        return RunningApp(name: name, bundleID: id)
      }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
}

/// Exclusions are bundle identifiers (AC-142). Adds go through `ExclusionsPaneModel`; the controller stores them.
@MainActor @Observable
final class ExclusionsModel {
  @ObservationIgnored private let preferences: PreferencesController
  @ObservationIgnored private let runningApps: @MainActor () -> [RunningApp]
  @ObservationIgnored private let nameForBundleID: (String) -> String?
  /// Names learned when an app was added, so its row reads by name even after it quits.
  private var learned: [String: String] = [:]

  init(
    preferences: PreferencesController, runningApps: @escaping @MainActor () -> [RunningApp] = RunningApp.current,
    nameForBundleID: @escaping (String) -> String? = ExclusionsModel.systemName(for:)
  ) {
    self.preferences = preferences
    self.runningApps = runningApps
    self.nameForBundleID = nameForBundleID
  }

  var rows: [ExclusionsPaneModel.Row] {
    let exclusions = preferences.preferences.exclusions
    var names: [String: String] = [:]
    for id in exclusions { names[id] = learned[id] ?? nameForBundleID(id) }
    return ExclusionsPaneModel.rows(exclusions, names: names.compactMapValues { $0 })
  }

  /// Running apps that are not excluded yet.
  var availableRunningApps: [RunningApp] {
    let excluded = preferences.preferences.exclusions
    return runningApps().filter { !excluded.contains($0.bundleID) }
  }

  func add(bundleID: String, name: String? = nil) {
    if let name { learned[bundleID] = name }
    preferences.update { ExclusionsPaneModel.add(bundleID: bundleID, to: &$0.exclusions) }
  }

  /// Adds the app at `url` by its bundle identifier. False, and nothing stored, when it has none.
  @discardableResult
  func add(appAt url: URL) -> Bool {
    guard let id = ExclusionsPaneModel.bundleID(forAppAt: url), !id.isEmpty else { return false }
    add(bundleID: id, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
    return true
  }

  func remove(_ bundleID: String) { preferences.update { $0.exclusions.remove(bundleID) } }

  nonisolated static func systemName(for bundleID: String) -> String? {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
  }
}

/// The excluded apps (name beside identifier), a running-apps menu and an "Add app…" file picker.
struct ExclusionsPane: View {
  let model: ExclusionsModel
  @State private var pickerFailed = false

  var body: some View {
    let rows = model.rows
    Form {
      Section("Excluded apps") {
        if rows.isEmpty { Text("No apps are excluded.").foregroundStyle(.secondary) }
        ForEach(rows, id: \.bundleID) { row in
          LabeledContent {
            Button("Remove", role: .destructive) { model.remove(row.bundleID) }
          } label: {
            VStack(alignment: .leading) {
              Text(row.name)
              if row.name != row.bundleID {
                Text(row.bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
              }
            }
          }
        }
      }
      Section("Add") {
        Menu("Running apps") {
          let running = model.availableRunningApps
          if running.isEmpty { Text("No other running apps") }
          ForEach(running, id: \.bundleID) { app in
            Button("\(app.name) (\(app.bundleID))") { model.add(bundleID: app.bundleID, name: app.name) }
          }
        }
        .fixedSize()
        Button("Add app…") { chooseApp() }
        if pickerFailed {
          Text("That item has no bundle identifier, so it cannot be excluded.").font(.callout).foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
  }

  private func chooseApp() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.message = "Choose an app to exclude"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    pickerFailed = !model.add(appAt: url)
  }
}
