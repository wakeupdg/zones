import Foundation
import ZonesCore
import ZonesLayout

/// What the router needs from the window: everything AppKit-specific stays behind this seam so tests need no AppKit.
@MainActor
protocol EditorEffectSink: AnyObject {
  func showUnsavedPrompt(switchingTo key: DisplayKey)
  func showMessage(_ text: String)
  func closeEditor()
}

/// Interprets `EditorEffect`s: persistence through `DocumentStore` (ADR-0017), the live `LayoutStore` through
/// `upsertLive`, and the window through the sink. Save is the only moment the live Layout changes.
@MainActor
final class EditorEffectRouter {
  private let store: DocumentStore
  private unowned let sink: any EditorEffectSink
  private let topology: () -> TopologySnapshot
  private let upsertLive: (Layout) -> Void
  private let now: () -> Date

  init(
    store: DocumentStore, sink: any EditorEffectSink, topology: @escaping () -> TopologySnapshot,
    upsertLive: @escaping (Layout) -> Void, now: @escaping () -> Date = Date.init
  ) {
    self.store = store
    self.sink = sink
    self.topology = topology
    self.upsertLive = upsertLive
    self.now = now
  }

  /// Runs `effects` in order and returns the document as it is on disk afterwards. A failed write leaves the
  /// document unchanged, shows the failure, and skips `replaceLive` for it (the live Layout never runs ahead of disk).
  func route(_ effects: [EditorEffect], document: ZonesDocument) -> ZonesDocument {
    var document = document
    var writeFailed = false
    for effect in effects {
      switch effect {
      case .writeLayouts(let next):
        do {
          try store.save(next, as: .layouts)
          document = next
        } catch {
          writeFailed = true
          sink.showMessage("Could not save the Layout: \(error.message)")
        }
      case .writeAssignment(let key, let layout):
        let next = assigning(layout, to: key, in: document)
        do {
          try store.save(next, as: .assignments)
          document = next
        } catch {
          sink.showMessage("Could not assign the Layout: \(error.message)")
        }
      case .replaceLive(let layout):
        if !writeFailed { upsertLive(layout) }
      case .promptUnsaved(let key):
        sink.showUnsavedPrompt(switchingTo: key)
      case .error(let error):
        sink.showMessage(Self.text(for: error))
      case .close:
        sink.closeEditor()
      }
    }
    return document
  }

  /// The inline text for a reducer refusal. The reducer owns the rules; this only words them.
  static func text(for error: EditorError) -> String {
    switch error {
    case .notSiblings(let hint): "Those Zones cannot be merged. \(hint)"
    case .tooSmall: "That would make a Zone too small."
    case .rootMerge: "The whole Layout is one Zone; there is nothing to merge."
    case .invalidRatio: "That divider cannot move any further."
    case .nothingSelected: "Select a Zone first."
    case .emptyName: "Give the Layout a name before you save it."
    case .surroundOutOfRange: "The space around the Zones is out of range (0 to 45 percent on each side)."
    }
  }

  /// `document` with the Display's Assignment pointing at `layout`. A connected Display refreshes its stored
  /// geometry and name; a disconnected one keeps what was stored (AC-125).
  private func assigning(_ layout: LayoutID, to key: PersistentDisplayKey, in document: ZonesDocument) -> ZonesDocument {
    var next = document
    let snapshot = topology().display(.uuid(key.uuid))
    let existing = document.assignments[key.uuid]
    next.assignments[key.uuid] = Assignment(
      layout: layout,
      displayName: snapshot?.name ?? existing?.displayName ?? key.uuid,
      lastVisibleFrame: snapshot?.visibleFrame ?? existing?.lastVisibleFrame ?? .zero,
      lastScale: snapshot?.scale ?? existing?.lastScale ?? 1,
      lastSeen: snapshot != nil ? now() : existing?.lastSeen)
    return next
  }
}
