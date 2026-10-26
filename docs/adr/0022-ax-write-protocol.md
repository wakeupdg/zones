# Frame writes go size, position, size; read back; toggle AXEnhancedUserInterface off during the write

There is no atomic AX frame call and writes report success even when clamped (research: ax-window-moves.md). Zones writes size, then position, then size again, reads the frame back, and keeps whatever the app accepted. Before a write it turns `AXEnhancedUserInterface` off on the app element and restores it after, to avoid animated or ignored moves in Chromium and Electron apps.

## Amendment 2026-10-24 (LOCKED-SPEC challenge C6)

No behavior change. Refinements: restore the Enhanced UI value in a defer on every path; skip the toggle when the attribute is absent or already off; drain pending restores on Quit and on permission revocation; keep a once-per-app recovery record with the prior value; expose an EnhancedUIPolicy of toggle (default) or leave.
