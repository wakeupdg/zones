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
    /// A `none` hit with an Original Frame: every fill dims and the drop restores (ADR-0009).
    var restore: Bool

    var highlight: Highlight {
      Highlight(display: display, primary: zones, secondary: secondary, dimAll: restore)
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

  /// The Span after the cursor moves to `cursor`: with the Span Modifier down, a Zone entered joins the set.
  /// Only a `.zone` hit adds; a Gap, Margin or surround (`.nearest`) is not a Zone entered.
  static func accumulate(_ span: SpanState, at cursor: Cursor, flags: ModifierSet, config: ModifierConfig)
    -> SpanState
  {
    var next = span
    guard flags.contains(ModifierSet(config.span)), !span.frozen, case .zone(let n) = cursor.hit else { return next }
    if next.zones.isEmpty { next.display = cursor.display }
    next.zones.insert(n)
    return next
  }

  /// What a drop at `cursor` does, given the Span as it stands after `accumulate`.
  static func drop(at cursor: Cursor, span: SpanState, in ctx: ArmContext) -> Drop {
    if case .none = cursor.hit {
      return Drop(display: cursor.display, zones: [], secondary: [], restore: ctx.hasOriginalFrame)
    }
    if !span.zones.isEmpty {
      return Drop(display: span.display, zones: span.zones, secondary: [], restore: false)
    }
    return Drop(display: cursor.display, zones: zones(of: cursor.hit), secondary: [], restore: false)
  }
}
