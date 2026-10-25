# Manual ACs — group A (Mac only)

12 ACs that need only the Mac, Zones and the keyboard. Do them in this order. Spec text: [LOCKED-SPEC.md](../LOCKED-SPEC.md).

Tester: DG  macOS version: 27.0.1  Date: 2026-10-24
App: /Applications/Zones.app (signed Debug build). Displays: LG Ultra HD (main), VG270K, built-in XDR.

AC-168 (release checklist) is not in this group. It uses results from all groups, so it comes last.

## How we work
1. Do the "Do" steps for one AC.
2. Tell Claude what you saw, in a few words.
3. Claude writes the result here. Then you go to the next AC.

## Before you start
1. Start Zones from /Applications.
2. Make sure that the Zones Accessibility toggle is **on**.
3. The tester's Activation Modifier is **Control** (Span modifier: Shift). "Drag" below means a drag with the Activation Modifier held. Note the opacity in Settings → Appearance before AC-141.

---

## Part 1 — Without the grant (2 ACs)

### [x] AC-020 — Cheat sheet and key caps
- **Do:**
  1. In System Settings → Privacy & Security → Device Control and Data Access (macOS 27; "Accessibility" on older macOS), turn the Zones toggle **off**. The onboarding window opens.
  2. Go to the last onboarding page.
  3. Open Settings → General. Change the Activation Modifier to **Command**.
  4. Look at the key cap on the last onboarding page.
- **Pass if:**
  - [x] The last page lists the 3 gestures.
  - [x] The key cap changes to the Command glyph (⌘).
- Result: **pass** (10:58 PM PT). Onboarding window opened after the Accessibility toggle off (macOS 27 path: Privacy & Security → Device Control and Data Access). Cheat sheet "How to use Zones" lists 3 gestures (see Zones while dragging; span several zones; send the front window to zone N). Key cap changed to ⌘ with the Activation Modifier set to Command; the tester then set it back to Control. First try failed for a test reason only: the Login Items "Allow in the Background" switch was turned off instead, and Background Task Management force-quit Zones.

### [ ] AC-106 — Shortcuts without the grant
- **Do:** Keep the toggle **off**.
  1. Press **Control+Option+E**.
  2. Close the editor. Click the "Zones key test" page in Safari (`scripts/qa/keytest.html`). Press **Control+Option+1**.
- **Pass if:**
  - [x] Control+Option+E opens the Zones editor.
  - [ ] The key test page shows the Send to Zone 1 chord. Zones does not take the chord.
- Then: turn the Zones toggle **on** again. Check that the Activation Modifier is **Control**.
- Result: **partial** (10:58 PM PT). Part 1 pass: Control+Option+E opened the editor with the grant off. Part 2 deferred: Control+Option+1 clashes with a MacParakeet shortcut on this Mac, so the result would not show Zones' behavior. New ticket T58 makes every chord Activation + Span + key; re-run part 2 with Control+Command+1 after T58 merges.

## Part 2 — Windows and keys (5 ACs)

### [x] AC-030 — About pane on screen
- **Do:** Open **About Zones** from the menu-bar icon. Do this in light appearance, then in dark appearance.
- **Pass if:**
  - [x] 1 window opens.
  - [x] You can read all 5 items in light and in dark.
  - [x] Exactly 1 line has "FancyZones", and it reads "inspired by FancyZones".
- Result: **pass** (11:00 PM PT). One About window; all 5 items legible in light and dark; one line reads "inspired by FancyZones".

### [x] AC-023 — Key status
- **Do:**
  1. Open **Settings…** from the menu-bar icon. Type a letter in a text field.
  2. Close Settings. Make TextEdit frontmost. Press **Control+Option+Comma**. Type a letter.
- **Pass if:**
  - [x] Step 1: the letter goes into Settings.
  - [x] Step 2: Settings is in front on the current Space.
  - [x] Step 2: the letter goes into Settings, not TextEdit. (macOS 27 expects key status, per SPK-014 and `SettingsWindowController`.)
- Result: **pass** (11:05 PM PT, dragprobe). Step 1: Settings from the menu became the key window (11:02:16 PM PT). Step 2 (re-run, Safari frontmost instead of TextEdit): Safari key 11:05:30.8 PM PT; Control+Option+Comma; Zones frontmost with key window "Zones Settings" 1.3 s later, so typing reaches Settings (macOS 27 expectation per SPK-014). First step-2 try did not count: Zones itself was still frontmost. Logs: [probe 1](logs/ac023-probe-1-2026-10-24.log), [probe 2](logs/ac023-probe-2-2026-10-24.log).

### [x] AC-107 — Editor and Settings chords
- **Do:** Put the pointer on the **VG270K** display.
  1. Press **Control+Option+E**. Close the editor.
  2. Press **Control+Option+Comma**.
- **Pass if:**
  - [x] The editor opens on the VG270K display.
  - [x] Settings opens.
- Result: **pass** (11:09 PM PT). Pointer at x = -1758 on VG270K (frame x -3008..0); "Zones Layout Editor" window bounds -3008, 162, 3008 × 1692 = the VG270K frame. Control+Option+Comma opened Settings.

### [x] AC-126 — Editor backdrop
- **Do:**
  1. Put 3 windows on the main display, where you can see them.
  2. Press **Control+Option+E**.
  3. With the editor open, Control-drag a window. Take a screenshot (Command+Shift+3) while the Overlay shows.
- **Pass if:**
  - [x] You can see all 3 windows through the editor backdrop.
  - [x] In the screenshot, the edges of Overlay Zone 1 and editor Zone 1 are the same.
- Result: **part 1 pass** (11:09 PM PT). Editor opened on VG270K (bounds = its frame); orchestrator screenshot of that display shows all 3 windows through the backdrop with Zones 1-3 drawn over them (screenshot not kept: private window content). Part 2 **pass** (11:11 PM PT): watcher captured the editor window bounds (-3008,162,3008,1692) while the Overlay showed (Overlay windows on all 3 displays, layer 1000). Lit Overlay Zone 1 = x 8-752 pt, y 8-1684 pt; 8 pt gap; Zone 2 starts at 760 pt. That is the editor Layout (Margin 8, Gap 8, 25/50/25 columns) exactly. Each edge shows one border only, no second editor edge within 25 pt. Capture deleted (private window content).

### [ ] AC-139 — Keyboard-only editor loop
- **Spec:** amended by C15 (T65). The loop starts from a Template copy; the editor has no "New Layout" action.
- **Do:** Do not touch the mouse after step 1.
  1. Open the editor (**Control+Option+E**). Click **Template** → **Focus 1** (the only one-Zone Template). Click the Zone once to select it. The editor is now the key window: do not click another window.
  2. Press **H** once, then **H** once. Do not hold a key. Then press **Command+S**, **Command+Shift+A**, **Command+W**.
  3. Control-drag a window on that display.
  4. Open Settings → Layouts.
- **Pass if:**
  - [ ] The Overlay shows 3 Zones side by side (25 / 25 / 50 percent of the center area).
  - [ ] The Layouts pane shows the new Layout, assigned to that display.
- **By spec (not a fail):** the name is "<Layout the editor opened on> copy", for example "Priority Grid copy" (AC-138 keeps the draft's name). The Zones sit in the center 60 percent (the Focus surround 0.2, C1).
- Result: **FAIL, re-run needed** (11:18 PM PT). Saved 11:17:24 PM, assigned 11:17:28 PM to VG270K (layouts.json id 67FA039B). Findings: (1) saved tree has 4 leaves (((½,½),½),½ nested = 12.5/12.5/25/50 %), not 3: an extra H, or a bug; (2) the Layout is named "Priority Grid copy" though it came from Focus 1; (3) it keeps the Focus surround 0.2, so the Zones sit in the center 60 % only; (4) Command+W did not close the editor: the editor was behind Safari and Settings, so the key went to another window. Overlay not captured. Spec gap: the editor has no "new Layout" action; AC-139 says "fresh Layout". Decision (11:24 PM PT): re-run first, with the editor as the key window; ticket only the findings that stay.

## Part 3 — Drags (4 ACs)

### [ ] AC-141 — Appearance applies live
- **Do:**
  1. In Settings, change the opacity from **0.3** to **0.8**. Change the Activation Modifier to **Command**.
  2. Do not relaunch. Command-drag a window.
- **Pass if:**
  - [ ] The Overlay shows at the new opacity on the first drag.
  - [ ] Command-drag starts the Overlay.
- Then: set the opacity and the modifier back to the values you noted (modifier: **Control**).
- Result:

### [ ] AC-044 — Drag uninterrupted
- **Do:**
  1. Tell Claude "start the probe". Claude runs `.build/dragprobe` (read-only).
  2. Click a TextEdit window. Control-drag it, hold it for 2 s, and drop it on a Zone.
  3. Tell Claude "done".
- **Pass if (Claude reads the probe log):**
  - [ ] The frontmost app and key window are the same before, during and after the drag.
  - [ ] Zones windows show at layer 1000 only during the drag.
- Result:

### [ ] AC-096 — Restore returns to the pre-grab place
- **Do:**
  1. Put a window on the **left** side of a display. Remember its position.
  2. Control-drag it into a Zone on the **right** side.
  3. Press **Control+Option+R**.
- **Pass if:**
  - [ ] The window goes back to its left-side position, not to the drop point.
- Result:

### [ ] AC-144 — Automatic skips on screen
- **Do:** Control-drag each of these:
  1. A Save sheet (TextEdit → File → Save…).
  2. A popover (for example, the Calendar event popover).
  3. The Zones Settings window.
  4. Calculator, dropped on a Zone.
- **Pass if:**
  - [ ] Items 1 to 3 show no Overlay.
  - [ ] Calculator moves to the Zone's top-left corner and does not change size.
- Result:

## Part 4 — Idle CPU (1 AC, 10 min)

### [ ] AC-157 — Idle CPU
- **Do:**
  1. Snap 20 windows into Zones.
  2. Tell Claude "start CPU". Then do not touch the Mac for 10 minutes.
- **Pass if (Claude measures the Zones CPU time over the 10 minutes):**
  - [ ] The Zones average CPU is less than 1 percent.
- Result:

## If an AC fails
Write what you saw in the Result line. Then tell Claude, and Claude makes a fix ticket.
