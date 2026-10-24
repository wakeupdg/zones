import CoreGraphics
import Foundation
import ZonesCore
import ZonesLayout

/// Pure helpers behind the armed branch of `DragSessionReducer`: what is under the cursor and what a drop would
/// do there. The highlight and the mouse-up both derive from one `Drop`, so they cannot disagree (LI-009).
enum SpanLogic {
  /// The Display under the cursor and the Hit in that Display's layout.
  struct Cursor: Hashable, Sendable {
    var display: DisplayKey?
    var hit: Hit
  }

  /// What dropping here would do, and therefore what the overlay shows.
  struct Drop: Hashable, Sendable {
    var display: DisplayKey?
    var zones: Set<Int>
    var secondary: Set<Int>
    /// The Display `secondary` belongs to: the suspended Span's Display, nil when there is no secondary set.
    var secondaryDisplay: DisplayKey?
    /// A `none` hit with an Original Frame: every fill dims and the drop restores (ADR-0009).
    var restore: Bool

    var highlight: Highlight {
      Highlight(
        display: display, primary: zones, secondary: secondary, secondaryDisplay: secondaryDisplay, dimAll: restore)
    }
  }

  /// `.none` when there is no Display or no layout for it.
  static func cursor(at point: CGPoint, in ctx: ArmContext) -> Cursor {
    let display = HitTest.display(at: point, in: ctx.topology)
    guard let display, let layout = ctx.layouts[display] else { return Cursor(display: display, hit: .none) }
    return Cursor(display: display, hit: HitTest.hit(point, in: layout))
  }

  static func zones(of hit: Hit) -> Set<Int> {
    switch hit {
    case .zone(let n), .nearest(let n): [n]
    case .none: []
    }
  }

  /// The Span after the modifiers change from `old` to `new`: releasing the Span Modifier freezes the set,
  /// pressing it again resumes adding, starting with the Zone already under the cursor.
  static func flagsChanged(
    _ span: SpanState, from old: ModifierSet, to new: ModifierSet, at cursor: Cursor, config: ModifierConfig
  ) -> SpanState {
    let spanKey = ModifierSet(config.span)
    var next = span
    if old.contains(spanKey), !new.contains(spanKey) {
      next.frozen = true
    } else if !old.contains(spanKey), new.contains(spanKey) {
      next.frozen = false
    }
    return accumulate(next, at: cursor, flags: new, config: config)
  }

  /// The Span after the cursor moves to `cursor`. A Span whose Display is not the cursor's is suspended: its set
  /// is kept untouched and nothing joins it until the cursor returns. Otherwise, with the Span Modifier down, a
  /// Zone entered joins the set; only a `.zone` hit adds, a Gap, Margin or surround (`.nearest`) does not.
  static func accumulate(_ span: SpanState, at cursor: Cursor, flags: ModifierSet, config: ModifierConfig)
    -> SpanState
  {
    var next = span
    next.suspended = !span.zones.isEmpty && span.display != cursor.display
    guard !next.suspended, flags.contains(ModifierSet(config.span)), !span.frozen, case .zone(let n) = cursor.hit
    else { return next }
    if next.zones.isEmpty { next.display = cursor.display }
    next.zones.insert(n)
    return next
  }

  /// What a drop at `cursor` does, given the Span as it stands after `accumulate`. While the Span is suspended
  /// the cursor Zone alone is the drop and the suspended set rides along as the secondary highlight on the Span's own Display.
  static func drop(at cursor: Cursor, span: SpanState, in ctx: ArmContext) -> Drop {
    let secondary = span.suspended ? span.zones : []
    let secondaryDisplay = span.suspended ? span.display : nil
    if case .none = cursor.hit {
      return Drop(
        display: cursor.display, zones: [], secondary: secondary, secondaryDisplay: secondaryDisplay,
        restore: ctx.hasOriginalFrame)
    }
    if span.suspended || span.zones.isEmpty {
      return Drop(
        display: cursor.display, zones: zones(of: cursor.hit), secondary: secondary,
        secondaryDisplay: secondaryDisplay, restore: false)
    }
    return Drop(display: span.display, zones: span.zones, secondary: [], secondaryDisplay: nil, restore: false)
  }

  /// The `updateHighlight` that moves the overlay from `old` to `new`; nothing when the highlight is unchanged.
  static func highlightChange(from old: DragState, to new: DragState) -> [DragEffect] {
    guard let was = highlight(of: old), let now = highlight(of: new), was != now else { return [] }
    return [.updateHighlight(now)]
  }

  /// The highlight an armed state shows: a pure function of its Display, Hit and Span (LI-009).
  static func highlight(of state: DragState) -> Highlight? {
    guard case .armed(_, _, _, _, let ctx, let display, let hit, let span, _) = state else { return nil }
    return drop(at: Cursor(display: display, hit: hit), span: span, in: ctx).highlight
  }
}
