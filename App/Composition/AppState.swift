import CoreGraphics
import Foundation
import ZonesCore
import ZonesLayout

/// Where the Preferences JSON blob lives (UserDefaults key "zones.preferences" in production).
protocol PreferenceStorage: Sendable {
  func load() -> Data?
  func save(_ data: Data)
}

struct UserDefaultsPreferenceStorage: PreferenceStorage {
  static let key = "zones.preferences"
  func load() -> Data? { UserDefaults.standard.data(forKey: Self.key) }
  func save(_ data: Data) { UserDefaults.standard.set(data, forKey: Self.key) }
}

/// The one place the app's persisted truth lives while it runs: Preferences, Layouts and Assignments.
/// Every write goes straight to its store (synchronous and atomic, AC-150). Drivers read; they never persist
/// on their own.
@MainActor
final class AppState {
  private(set) var preferences: Preferences
  private(set) var layouts: LayoutStore
  private(set) var assignments: [String: Assignment]
  private let documents: DocumentStore
  private let storage: any PreferenceStorage

  init(documents: DocumentStore, storage: any PreferenceStorage) {
    self.documents = documents
    self.storage = storage
    var prefs = Preferences.defaults
    if let data = storage.load() {
      let (decoded, coerced) = PreferencesCodec.decode(data)
      prefs = decoded
      if !coerced.isEmpty { prefs.notices.insert(.preferencesCoerced) }
    }
    preferences = prefs.coerced()
    layouts = LayoutStore(
      document: Self.document(documents.load(.layouts)), defaults: preferences.appearance.defaultInsets)
    assignments = Self.document(documents.load(.assignments)).assignments
  }

  private static func document(_ result: LoadResult) -> ZonesDocument {
    switch result {
    case .loaded(let document), .migrated(let document, _, _): document
    case .defaults, .newerLeftUntouched: ZonesDocument()
    }
  }

  // MARK: Layouts and Assignments

  /// Custom Layouts and every Assignment as one document, the shape the editor and Settings load and write.
  var document: ZonesDocument {
    ZonesDocument(version: Constants.documentVersion, layouts: layouts.custom, assignments: assignments)
  }

  /// Adopts a custom Layout a writer has just persisted (the editor's Save). Built-ins are ignored.
  func upsertLayout(_ layout: Layout) { layouts.upsert(layout) }

  /// Drops a custom Layout and moves every Assignment that used it to `replacement`. Returns false (nothing
  /// changed) for a built-in, an unknown id, a missing or invalid replacement.
  @discardableResult
  func deleteLayout(_ id: LayoutID, replacement: LayoutID?) -> Bool {
    var nextLayouts = layouts
    var nextAssignments = assignments
    guard case .success = nextLayouts.delete(id, replacement: replacement, assignments: &nextAssignments) else {
      return false
    }
    layouts = nextLayouts
    assignments = nextAssignments
    return true
  }

  /// Adopts the document a writer (the editor, Settings > Layouts) has just persisted: the next drag arm,
  /// shortcut and menu build read it with no relaunch.
  func replaceDocument(_ document: ZonesDocument) {
    layouts = LayoutStore(document: document, defaults: preferences.appearance.defaultInsets)
    assignments = document.assignments
  }

  /// Re-reads layouts.json and assignments.json, for a writer that cannot hand its document over.
  func reload() {
    replaceDocument(
      ZonesDocument(
        version: Constants.documentVersion, layouts: Self.document(documents.load(.layouts)).layouts,
        assignments: Self.document(documents.load(.assignments)).assignments))
  }

  // MARK: Writes

  func setPreferences(_ new: Preferences) {
    let coerced = new.coerced()
    guard coerced != preferences else { return }
    let insetsChanged = coerced.appearance.defaultInsets != preferences.appearance.defaultInsets
    preferences = coerced
    if insetsChanged { layouts.setDefaults(coerced.appearance.defaultInsets) }
    storage.save(PreferencesCodec.encode(coerced))
  }

  func setShortcuts(_ shortcuts: [Shortcut]) {
    var next = preferences
    next.shortcuts = shortcuts
    setPreferences(next)
  }

  func toggleExclusion(_ bundleID: String) {
    var next = preferences
    if next.exclusions.contains(bundleID) { next.exclusions.remove(bundleID) } else { next.exclusions.insert(bundleID) }
    setPreferences(next)
  }

  func insertNotice(_ flag: NoticeFlag) {
    var next = preferences
    next.notices.insert(flag)
    setPreferences(next)
  }

  /// A topology-driven write (name, visible frame or scale drifted, or a pick).
  func setAssignment(_ key: PersistentDisplayKey, _ assignment: Assignment) {
    assignments[key.uuid] = assignment
    let document = ZonesDocument(assignments: assignments)
    do { try documents.save(document, as: .assignments) } catch {
      Log.shared.event(
        LogEvent(
          time: ProcessInfo.processInfo.systemUptime, category: .core, level: .error,
          message: "assignments not saved: \(error.message)"))
    }
  }

  // MARK: Reads

  /// The resolved Layout of every Display in `topology`. Overlay and Snap read these same rectangles.
  func resolvedLayouts(
    for topology: TopologySnapshot, session: [DisplayKey: LayoutID]
  ) -> [DisplayKey: ResolvedLayout] {
    var out: [DisplayKey: ResolvedLayout] = [:]
    for display in topology.displays {
      let id = AssignmentLookup.layoutID(for: display.key, in: assignments, session: session)
      let fallback = Templates.builtInID(.priorityGrid, count: 3)
      guard let layout = layouts.layout(id) ?? layouts.layout(fallback) else { continue }
      out[display.key] = LayoutMath.resolve(layout, display: display)
    }
    return out
  }

  func assignedLayoutID(for key: DisplayKey, session: [DisplayKey: LayoutID]) -> LayoutID {
    AssignmentLookup.layoutID(for: key, in: assignments, session: session)
  }
}
