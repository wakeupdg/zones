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

### [x] AC-005 — Grant noticed without relaunch
- **Do:** Note the Zones process id (`pgrep -x Zones`). Start the stopwatch. Turn the Zones toggle **on**.
- **Pass if:**
  - [x] The onboarding window closes in **under 1.5 s**.
  - [x] The menu-bar icon has no badge.
  - [x] The process id did not change (no relaunch).
- Result: **pass** (re-test 9:02 PM PT, 2026-10-24; signed Debug build in /Applications, pid 4835, Zones Dev cert 13d6ab…, after T55). Toggle on at re-grant: window closed and badge gone **0.55 s** later; process id unchanged. First grant (entry added with +): window closed in the same 50 ms sample as the badge cleared. Log: [logs/ac005-ac009-retest-2026-10-24.log](logs/ac005-ac009-retest-2026-10-24.log).

### [x] AC-009 — Revocation on a real Mac — **pass after T55**
- **Do:** With Zones idle, turn the toggle **off**. Start the stopwatch.
- **Pass if:**
  - [x] The icon shows a badge in **8 s or less** (AC-009 as amended by C12, T55).
  - [x] The onboarding window comes back.
  - [x] You recorded the probe value from the diagnostics report.
- **CAUTION:** Copy Diagnostics has no menu item yet (CHANGELOG known issue). If you cannot get the report, write "no UI" here and continue.
- Result (re-test 9:01 PM PT, 2026-10-24, after T55): **pass**. Toggle off while idle: badge and onboarding window back in **3.8 s** (limit 8 s); the stale-entry help line followed 10.0 s later; process id unchanged; probe value: `AXIsProcessTrusted` false (no diagnostics UI). Log: [logs/ac005-ac009-retest-2026-10-24.log](logs/ac005-ac009-retest-2026-10-24.log).
- First result: **FAIL** (human run 6:06 PM PT, 2026-10-24; Debug build pid 43679, Zones Dev signed). Toggle off for about 12.5 min: no badge, no onboarding window, process id unchanged. A Shift-drag while off showed no overlay and did not snap, so macOS did stop access but Zones did not detect it. Probe value: no UI. Cause: `heartbeatEnabled = false` (SPK-006 provisional default); a revoked listen-only tap gets no events, so no Drag Session starts and no AX error arrives. Watcher log: [logs/ac009-watch-2026-10-24.log](logs/ac009-watch-2026-10-24.log).

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
