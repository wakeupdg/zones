import Foundation

/// Undo and redo as value arrays of whole drafts: an undo restores the stored draft, it never computes an inverse,
/// so the round trip is exact. Every changing command, `select` included, is recorded.
public struct UndoStack: Hashable, Sendable {
  public var undo: [EditorDraft]
  public var redo: [EditorDraft]

  public init(undo: [EditorDraft] = [], redo: [EditorDraft] = []) {
    self.undo = undo
    self.redo = redo
  }

  /// Pushes `before` and drops the redo history, but only when the command changed something.
  public mutating func record(before: EditorDraft, after: EditorDraft) {
    guard before != after else { return }
    undo.append(before)
    redo.removeAll()
  }

  /// The draft to show after an undo, or nil when there is nothing to undo. `current` moves onto the redo array.
  public mutating func undo(current: EditorDraft) -> EditorDraft? {
    guard let previous = undo.popLast() else { return nil }
    redo.append(current)
    return previous
  }

  /// The draft to show after a redo, or nil when there is nothing to redo. `current` moves back onto the undo array.
  public mutating func redo(current: EditorDraft) -> EditorDraft? {
    guard let next = redo.popLast() else { return nil }
    undo.append(current)
    return next
  }
}
