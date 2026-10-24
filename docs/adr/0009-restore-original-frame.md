# Original frame is captured at first snap, restored by shortcut or by a modifier-drag that ends over no zone

Zones records a window frame the first time it snaps that window and forgets it when the window closes. Restore happens on the Restore shortcut, or when an activation-modifier drag ends outside every zone. A plain drag without the modifier never restores (the user is positioning by hand). Rejected: restore on any drag (surprising) and shortcut-only (no mouse path).

## Amendment 2026-10-24 (LOCKED-SPEC challenge C2)

"Ends outside every zone" is refined to "ends outside the Display's visible frame" (the menu bar or Dock strip). An activation-modifier drag that ends on a Gap, Margin or surround Snaps to the nearest Zone (minimum edge distance, ties to the lower Zone Number) and never Restores, so an 8-point miss cannot teleport a window. The Overlay stays up during such a drag with the highlight cleared and every fill dimmed only when an Original Frame exists.

The Original Frame is forgotten when the window closes, when its app quits, and on a successful Restore (result applied or clamped), so Snap, Restore, hand-move, Snap, Restore returns the hand-placed frame. Capture points: on the mouse path the mouse-down frame of the resolved window; on the keyboard path the pre-write read-back frame; later Snaps never overwrite it. A Span Snap records the same kind of entry as a single-Zone Snap. Restore of a frame that intersects no Display is clamped into the visible frame of the Display the window overlaps most.
