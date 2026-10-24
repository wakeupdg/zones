# Besides per-app exclusions, Zones skips windows it cannot or should not move

Skipped automatically: windows whose size or position is not settable (`AXUIElementIsAttributeSettable`), sheets, popovers, non-standard subroles, system dialogs, and Zones own windows (by pid). Per-app exclusions are by bundle id.
