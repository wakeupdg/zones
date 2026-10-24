# Besides per-app exclusions, Zones skips windows it cannot or should not move

Skipped automatically: windows whose size or position is not settable (`AXUIElementIsAttributeSettable`), sheets, popovers, non-standard subroles, system dialogs, and Zones own windows (by pid). Per-app exclusions are by bundle id.

## Amendment 2026-10-24 (LOCKED-SPEC challenge C4)

"Size or position is not settable" reads "position is not settable". A window whose position cannot be set is skipped. A window whose size cannot be set but whose position can (Calculator, inspector panels) is not skipped: it receives a position-only Snap at the Zone's top-left inside the visible frame with no size write, and cycles and Restores by position alone. Phase 1 (CoreGraphics facts only, before any Accessibility call) also skips Zones' own pid, system agents (Dock, WindowManager, Notification Center, Control Center, loginwindow, UserNotificationCenter), excluded bundle identifiers and pids inside the unresponsive cooldown; phase 2 (Accessibility facts) skips non-standard subroles, sheets and popovers, system dialogs (subroles systemDialog and systemFloatingWindow), full-screen windows (ADR-0014) and positionNotSettable. Every skip is logged once with its reason.
