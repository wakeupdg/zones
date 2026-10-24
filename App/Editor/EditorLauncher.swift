import AppKit
import Foundation
import os
import ZonesCore
import ZonesLayout
import ZonesWindowing

/// The editor's door (AC-126): "Edit Layouts…" and Control+Option+E both end in `openEditor()`. It owns the
/// `EditorWindowController` and feeds it the app's `DocumentStore`, live `LayoutStore` and topology.
/// T36's composition root takes over the object graph (one registrar, preferences-driven chord, shared
/// `LayoutStore`); until then this is the only owner of the editor's dependencies.
@MainActor
final class EditorLauncher {
  /// The Layout the editor opens on: the one assigned to the Display under the cursor, else Priority Grid 3
  /// (the same fallback `AssignmentLookup` gives every unassigned Display).
  nonisolated static func layoutToEdit(
    display: DisplaySnapshot?, store: LayoutStore, assignments: [String: Assignment]
  ) -> Layout {
    let fallback = Templates.builtInID(.priorityGrid, count: 3)
    var id = fallback
    if let display { id = AssignmentLookup.layoutID(for: display.key, in: assignments, session: [:]) }
    return store.layout(id) ?? store.layout(fallback) ?? Templates.generate(.priorityGrid, count: 3, insets: Insets(margin: 8, gap: 8))
  }

  private let documents: DocumentStore
  private let provider: any DisplayProvider
  private let registrar: any HotkeyRegistrar
  private let cursor: () -> CGPoint
  private var layouts: LayoutStore
  private var controller: EditorWindowController?
  private var presses: Task<Void, Never>?

  init(
    documents: DocumentStore, provider: any DisplayProvider, registrar: any HotkeyRegistrar,
    preferences: Preferences = .defaults, cursor: @escaping () -> CGPoint = { NSEvent.mouseLocation }
  ) {
    self.documents = documents
    self.provider = provider
    self.registrar = registrar
    self.cursor = cursor
    layouts = LayoutStore(
      document: Self.document(documents, .layouts), defaults: preferences.appearance.defaultInsets)
    let appearance = preferences.appearance
    controller = EditorWindowController(
      topology: { [provider] in provider.snapshot() }, cursor: cursor, store: documents,
      loadDocument: { [documents] in
        ZonesDocument(
          version: Constants.documentVersion, layouts: Self.document(documents, .layouts).layouts,
          assignments: Self.document(documents, .assignments).assignments)
      },
      documentChanged: { _ in },
      upsertLive: { [weak self] layout in self?.layouts.upsert(layout) },
      appearance: { appearance })
  }

  /// Production wiring: ~/Library/Application Support/Zones, the real displays and Carbon hotkeys.
  static func production() -> EditorLauncher {
    let support =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
    let store = DocumentStore(
      fs: FoundationFileSystem(), directory: support.appending(path: "Zones"), clock: UptimeClock())
    return EditorLauncher(documents: store, provider: ScreenDisplayProvider(), registrar: CarbonHotkeyRegistrar())
  }

  /// Binds the default Control+Option+E chord and opens the editor on each press. A chord another app already
  /// holds leaves the menu item as the way in.
  func start() {
    if let chord = Preferences.defaults.shortcuts.first(where: { $0.action == .openEditor })?.chord {
      _ = registrar.register(chord, for: .openEditor)
    }
    presses?.cancel()
    presses = Task { @MainActor [weak self, registrar] in
      for await action in registrar.presses where action == .openEditor { self?.openEditor() }
    }
  }

  func openEditor() {
    guard let controller else { return }
    let display = WindowPlacement.cursorDisplay(cursor: cursor(), in: provider.snapshot())
    let assignments = Self.document(documents, .assignments).assignments
    controller.show(layout: Self.layoutToEdit(display: display, store: layouts, assignments: assignments))
  }

  private static func document(_ store: DocumentStore, _ kind: DocumentKind) -> ZonesDocument {
    switch store.load(kind) {
    case .loaded(let document), .migrated(let document, _, _): document
    case .defaults, .newerLeftUntouched: ZonesDocument(version: Constants.documentVersion)
    }
  }
}

/// A `Clock` for `DocumentStore`, which only reads `now` for log timestamps. Timers are real
/// (`DispatchSourceTimer` on the main queue) so the type honours the protocol if that ever changes; T36's
/// `ProductionClock` replaces it.
final class UptimeClock: Clock {
  private struct Timers {
    var next: UInt64 = 0
    var live: [TimerHandle: DispatchSourceTimer] = [:]
  }
  private let timers = OSAllocatedUnfairLock(initialState: Timers())

  var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

  func schedule(
    _ id: TimerID, after seconds: TimeInterval, repeats: Bool, _ fire: @Sendable @escaping () -> Void
  ) -> TimerHandle {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + seconds, repeating: repeats ? seconds : .infinity)
    timer.setEventHandler(handler: fire)
    let handle = timers.withLock { state in
      state.next += 1
      let handle = TimerHandle(id: id, token: state.next)
      state.live[handle] = timer
      return handle
    }
    timer.resume()
    return handle
  }

  func cancel(_ handle: TimerHandle) {
    timers.withLock { $0.live.removeValue(forKey: handle) }?.cancel()
  }
}
