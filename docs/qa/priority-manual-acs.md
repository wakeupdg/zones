# Priority manual ACs (permission and drag)

Do these 6 first. They test the most important user flows. Full list: [acceptance-matrix.md](acceptance-matrix.md). Spec text: [LOCKED-SPEC.md](../LOCKED-SPEC.md).

Tester: DG  macOS version: 27.0.1  Date: 2026-10-24 (results recorded 12:18 PM PT)

## Before you start
1. Install `dist/Zones-0.1.0.dmg`. The app is ad-hoc signed, so open it with right-click → Open.
2. For a "clean account" start, reset the permission:
   `tccutil reset Accessibility com.dganesh.zones`
3. Have a stopwatch ready (AC-005, AC-009, AC-010).

## 1. Permission flow — do these in order

### [x] AC-004 — Onboarding window
- **Do:** Launch Zones after the reset.
- **Pass if:**
  - [x] Exactly **1** window opens.
  - [x] Its button opens System Settings → Privacy & Security → **Accessibility**, and that pane is in front.
- Result: **pass** (human run, 2026-10-24)

### [ ] AC-005 — Grant noticed without relaunch
- **Do:** Note the Zones process id (`pgrep -x Zones`). Start the stopwatch. Turn the Zones toggle **on**.
- **Pass if:**
  - [ ] The onboarding window closes in **under 1.5 s**.
  - [ ] The menu-bar icon has no badge.
  - [ ] The process id did not change (no relaunch).
- Result: **not run yet**

### [ ] AC-009 — Revocation on a real Mac
- **Do:** With Zones idle, turn the toggle **off**. Start the stopwatch.
- **Pass if:**
  - [ ] The icon shows a badge at the next drag, or in **5 s or less** if the heartbeat is on.
  - [ ] The onboarding window comes back.
  - [ ] You recorded the probe value from the diagnostics report.
- **CAUTION:** Copy Diagnostics has no menu item yet (CHANGELOG known issue). If you cannot get the report, write "no UI" here and continue.
- Result: **not run yet**

### [x] AC-010 — Re-grant recovery
- **Do:** Turn the toggle **on** again. Shift-drag a window.
- **Pass if one of these is true:**
  - [ ] Dragging works again in **3 s or less**, with no relaunch, **or**
  - [ ] After about **10 s**, a **"Quit and Reopen"** button appears. You press it, and the new app snaps windows with no onboarding window.
- Result: **pass** (human run, 2026-10-24; which path was not recorded)

## 2. Drag behavior

### [x] AC-057 — Four identical terminals
- **Do:** Open 4 Terminal windows at the same size, stacked. Shift-drag each one in turn.
- **Pass if, for each of the 4:**
  - [x] Only the window you drag moves.
  - [x] The overlay appears.
- Result: **pass** (human run, 2026-10-24)

### [x] AC-066 — Modifier never consumed
- **Do:** Do both gestures with Zones running. Then quit Zones and do them again. Compare.
  - Finder: Shift-click to select a range of files.
  - A drawing app (for example Preview markup): Shift-drag to draw a straight line.
- **Pass if:**
  - [x] Both gestures work the same with and without Zones.
- Result: **pass** (human run, 2026-10-24)

## If an AC fails
Write what you saw in the Result line. Then tell Claude, and Claude makes a fix ticket.
