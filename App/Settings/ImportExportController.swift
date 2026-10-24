import AppKit
import Observation
import UniformTypeIdentifiers
import ZonesCore
import ZonesLayout
import ZonesWindowing

/// The two file panels the Layouts pane opens. Injected so tests never show a panel.
struct FilePanels {
  var chooseImport: @MainActor () -> URL?
  var chooseExport: @MainActor (_ suggestedName: String) -> URL?

  static let none = FilePanels(chooseImport: { nil }, chooseExport: { _ in nil })

  static let system = FilePanels(
    chooseImport: {
      let panel = NSOpenPanel()
      panel.allowedContentTypes = [.json]
      panel.allowsMultipleSelection = false
      panel.canChooseDirectories = false
      panel.message = "Choose a Zones layouts file to import"
      return panel.runModal() == .OK ? panel.url : nil
    },
    chooseExport: { name in
      let panel = NSSavePanel()
      panel.allowedContentTypes = [.json]
      panel.nameFieldStringValue = name
      panel.message = "Export Layouts"
      return panel.runModal() == .OK ? panel.url : nil
    })
}

/// Owns the `LayoutsFlow` for the Settings window: runs the open and save panels, reads and writes the chosen
/// files, and forwards the Layout and Display actions. All decisions live in `LayoutsFlow`; views only call here.
@MainActor @Observable
final class ImportExportController {
  private(set) var flow: LayoutsFlow
  /// One line after a successful export, or the reason it failed.
  private(set) var exportStatus: String?

  @ObservationIgnored private let fs: any FileSystem
  @ObservationIgnored private let panels: FilePanels
  @ObservationIgnored private let attached: () -> Set<String>
  @ObservationIgnored private let now: () -> TimeInterval

  init(
    flow: LayoutsFlow, fs: any FileSystem, panels: FilePanels = .system,
    attached: @escaping () -> Set<String> = { [] },
    now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
  ) {
    self.flow = flow
    self.fs = fs
    self.panels = panels
    self.attached = attached
    self.now = now
  }

  /// The production controller: documents from ~/Library/Application Support/Zones.
  static func live(defaults: Insets, topology: @escaping () -> TopologySnapshot?) -> ImportExportController {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let fs = FoundationFileSystem()
    let documents = DocumentStore(fs: fs, directory: base.appending(path: "Zones"), clock: SystemClock())
    func document(_ kind: DocumentKind) -> ZonesDocument {
      switch documents.load(kind) {
      case .loaded(let document), .migrated(let document, _, _): document
      case .defaults, .newerLeftUntouched: ZonesDocument()
      }
    }
    let flow = LayoutsFlow(
      documents: documents, layouts: document(.layouts), assignments: document(.assignments).assignments,
      defaults: defaults)
    return ImportExportController(
      flow: flow, fs: fs,
      attached: {
        Set((topology()?.displays ?? []).compactMap { if case .uuid(let uuid) = $0.key { uuid } else { nil } })
      })
  }

  // MARK: Export and import

  func exportAll() { export(only: nil, suggestedName: "zones-layouts.json") }

  func export(layout id: LayoutID) {
    let name = flow.store.layout(id)?.name ?? "layout"
    export(only: id, suggestedName: "\(name).json")
  }

  private func export(only: LayoutID?, suggestedName: String) {
    guard let url = panels.chooseExport(suggestedName) else { return }
    do {
      try flow.writeExport(only: only, to: url, fs: fs)
      exportStatus = "Exported to \(url.lastPathComponent)."
    } catch {
      exportStatus = error.importText
    }
  }

  /// Opens the panel, reads the file and decodes it; a readable file opens the Merge/Replace sheet.
  func startImport() {
    exportStatus = nil
    guard let url = panels.chooseImport() else { return }
    do {
      flow.beginImport(try fs.read(url), fileName: url.lastPathComponent)
    } catch {
      flow.reportImportFailure(.io(String(describing: error)))
    }
  }

  func cancelImport() { flow.cancelImport() }

  var replaceBackupName: String? { flow.replaceBackupName(now: now()) }

  func applyImport(_ mode: ImportMode) {
    flow.applyImport(mode, attached: attached(), now: now())
  }

  // MARK: Layout and Display actions

  func duplicate(_ id: LayoutID) { flow.duplicate(id) }
  func rename(_ id: LayoutID, to name: String) -> Bool { succeeded(flow.rename(id, to: name)) }
  func delete(_ id: LayoutID, replacement: LayoutID?) -> Bool { succeeded(flow.delete(id, replacement: replacement)) }
  func copyAssignment(from key: String, to target: DisplaySnapshot) { flow.copyAssignment(from: key, to: target) }
  func forget(_ key: String) { flow.forget(key) }
  func pick(_ layout: LayoutID, for display: DisplaySnapshot) { flow.pick(layout, for: display) }

  /// Changing the default Margin and Gap regenerates the built-ins (AC-117).
  func setDefaultInsets(_ insets: Insets) { flow.setDefaultInsets(insets) }

  private func succeeded(_ result: LayoutsFlow.ActionResult) -> Bool {
    if case .success = result { true } else { false }
  }
}

/// A wall clock for `DocumentStore`: its timers are not used by the Settings window.
struct SystemClock: ZonesCore.Clock {
  var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
  func schedule(
    _ id: TimerID, after seconds: TimeInterval, repeats: Bool, _ fire: @Sendable @escaping () -> Void
  ) -> TimerHandle {
    TimerHandle(id: id, token: 0)
  }
  func cancel(_ handle: TimerHandle) {}
}
