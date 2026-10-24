import CoreGraphics
import Foundation
import ZonesCore

/// The editor's whole state. `preview` and `warnings` are recomputed from `draft` in every step that changes the
/// draft or the Display, so nothing derived from them (labels, rectangles) can go stale.
public struct EditorState: Hashable, Sendable {
  public var draft: EditorDraft
  public var undo: [EditorDraft]
  public var redo: [EditorDraft]
  public var display: DisplayKey
  public var visibleFrame: CGRect
  public var scale: Double
  public var preview: ResolvedLayout
  public var warnings: Set<Int>

  public init(
    draft: EditorDraft, undo: [EditorDraft], redo: [EditorDraft], display: DisplayKey, visibleFrame: CGRect,
    scale: Double, preview: ResolvedLayout, warnings: Set<Int>
  ) {
    self.draft = draft
    self.undo = undo
    self.redo = redo
    self.display = display
    self.visibleFrame = visibleFrame
    self.scale = scale
    self.preview = preview
    self.warnings = warnings
  }
}

public enum EditorEvent: Hashable, Sendable {
  case command(EditorCommand), undo, redo, switchDisplay(DisplayKey, confirmed: Bool), assign, save, cancel
}

public enum EditorEffect: Hashable, Sendable {
  case promptUnsaved(DisplayKey), writeLayouts(ZonesDocument), writeAssignment(PersistentDisplayKey, LayoutID),
    replaceLive(Layout), close, error(EditorError)
}

/// The pure editor reducer. It never touches a `DocumentStore`: the caller interprets the effects.
public enum EditorModel {
  /// Connected Display: the snapshot. Disconnected (AC-125): the stored `Assignment` geometry.
  public static func open(
    _ l: Layout, display: DisplayKey, topology: TopologySnapshot, assignments: [String: Assignment]
  ) -> EditorState {
    let geometry = resolveGeometry(display, topology: topology, assignments: assignments)
    return state(
      draft: EditorDraft(layout: l, selection: nil, dirty: false), undo: [], redo: [], display: display,
      geometry: geometry)
  }

  public static func reduce(
    _ s: EditorState, _ e: EditorEvent, context: (topology: TopologySnapshot, document: ZonesDocument)
  ) -> (EditorState, [EditorEffect]) {
    switch e {
    case .command(let c):
      switch EditorEngine.apply(c, to: s.draft, geometry: (s.visibleFrame, s.scale)) {
      case .failure(let error):
        return (s, [.error(error)])
      case .success(let next):
        var stack = UndoStack(undo: s.undo, redo: s.redo)
        stack.record(before: s.draft, after: next)
        return (restored(s, draft: next, stack: stack), [])
      }
    case .undo:
      var stack = UndoStack(undo: s.undo, redo: s.redo)
      guard let previous = stack.undo(current: s.draft) else { return (s, []) }
      return (restored(s, draft: previous, stack: stack), [])
    case .redo:
      var stack = UndoStack(undo: s.undo, redo: s.redo)
      guard let next = stack.redo(current: s.draft) else { return (s, []) }
      return (restored(s, draft: next, stack: stack), [])
    case .switchDisplay, .assign, .save, .cancel:
      return (s, [])
    }
  }

  /// The editor's label model: the shared `LabelModel` over the live preview (AC-132).
  public static func labels(_ s: EditorState, appearance: Appearance) -> [ZoneLabel] {
    LabelModel.labels(s.preview, appearance: appearance)
  }

  // MARK: helpers

  private typealias Geometry = (visibleFrame: CGRect, scale: Double)

  /// Snapshot, else the stored Assignment geometry, else the main Display (else the first one).
  private static func resolveGeometry(
    _ key: DisplayKey, topology: TopologySnapshot, assignments: [String: Assignment]
  ) -> Geometry {
    if let snap = topology.display(key) { return (snap.visibleFrame, snap.scale) }
    if case .uuid(let u) = key, let stored = assignments[u] { return (stored.lastVisibleFrame, stored.lastScale) }
    if let main = topology.displays.first(where: \.isMain) ?? topology.displays.first {
      return (main.visibleFrame, main.scale)
    }
    return (topology.primaryFrame, 1)
  }

  /// `s` with a new draft and stacks; `preview` and `warnings` are recomputed in the same step.
  private static func restored(_ s: EditorState, draft: EditorDraft, stack: UndoStack) -> EditorState {
    state(draft: draft, undo: stack.undo, redo: stack.redo, display: s.display, geometry: (s.visibleFrame, s.scale))
  }

  private static func state(
    draft: EditorDraft, undo: [EditorDraft], redo: [EditorDraft], display: DisplayKey, geometry: Geometry
  ) -> EditorState {
    let preview = LayoutMath.resolve(
      draft.layout, key: display, visibleFrame: geometry.visibleFrame, scale: geometry.scale)
    return EditorState(
      draft: draft, undo: undo, redo: redo, display: display, visibleFrame: geometry.visibleFrame,
      scale: geometry.scale, preview: preview, warnings: EditorEngine.warnings(preview))
  }
}
