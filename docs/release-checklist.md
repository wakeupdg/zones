# Release checklist

Release tag:
macOS version:
Tester:

Mark each Result `pass` or `fail` on the release tag. A `fail` or a blank Result blocks the release.

| # | Check | Pass condition (AC) | Result |
| --- | --- | --- | --- |
| 1 | Grant from a clean account | One onboarding window, dismissed within 1.5 s of the toggle: AC-004, AC-005 | |
| 2 | Shift-drag on every Display, drop on a Zone | Lands on the Overlay rectangle, no other window moves: AC-070 | |
| 3 | Drop on a Gap | Snaps into the nearest Zone, never Restores: AC-080 | |
| 4 | Drop on the menu bar, with and without an Original Frame | With: fills dim, window returns to its pre-grab frame (AC-091, AC-096). Without: nothing dims, window stays where macOS left it (AC-091) | |
| 5 | Pause on the title bar, then drag | Overlay appears, Snap works: AC-055 | |
| 6 | Control-sweep a diagonal Span, release Control, skim a seam, drop | Union of the swept Zones on the Span's Display: AC-081, AC-083, AC-085 | |
| 7 | Send to each Zone by chord, including N beyond the count | Lands in Zone N; the absent N does nothing: AC-098, AC-101 | |
| 8 | Chord mid-drag | Ignored, one log line: AC-110 | |
| 9 | Cycle after a Span and after a clamp | Next Zone per the cycle table: AC-100 | |
| 10 | Restore, hand-move, Snap, Restore | Returns to the hand-placed frame: AC-093 | |
| 11 | Revoke mid-drag and while idle | Badge and onboarding window return, no crash: AC-007, AC-009 | |
| 12 | Unplug a Display mid-session | Overlay re-arms from the new geometry, no window moves: AC-060, AC-119 | |
| 13 | Mirror, pick a Layout, unmirror | Mirror set keyed by the master, each Display resumes its own Assignment: AC-122 | |
| 14 | Import with Merge and with Replace | Merged names suffixed, Replace writes a named backup first: AC-146 | |
| 15 | Stage Manager on, Shift-drag on the current stage | Snaps, and no window on another stage moves: AC-070, AC-041 | |
