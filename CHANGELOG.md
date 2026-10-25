# Changelog

All notable changes to Zones are listed here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- App icon (Icon Composer `App/AppIcon.icon`, Liquid Glass tiles on macOS 26, flat fallback for 14/15) and the direction B menu-bar glyph in place of the SF Symbol.

### Fixed

- `Templates.generate` refuses a count its Template does not offer (it returns nil); Grid 6 no longer builds a
  2 x 2 grid (T12, T65).
- `LayoutValidator` reports `.overlap` when a ratio below 0 or above 1 makes two leaves share area; import tests
  cover the AC-151 overlap variant (T17, T65).
- The editor reports an empty name and a surround fault with their own messages, not as an invalid ratio
  (`EditorError.emptyName`, `.surroundOutOfRange`; T28/T30, T65).
- The Exclusions pane sorts names like Finder (`localizedStandardCompare`, so "App 2" comes before "App 10";
  T14, T65).

## [0.1.0] - 2026-10-24

First pre-release. Built and unit-tested, but not yet verified on real hardware.

### Added

#### Drag-to-Zone snapping

- Hold the Activation Modifier (Shift by default) while dragging a window to show the Zones overlay.
- The Zone under the cursor highlights. Releasing snaps the window to it.
- A drop on a Gap, Margin or surround snaps to the nearest Zone, so a small miss never fails silently.
- A listen-only event tap watches mouse and modifier events. It never blocks or changes them.
- Size, position, size, read-back write protocol, with one retry and a 250 ms timeout per app.
- Size-locked windows get a position-only Snap on both the mouse and keyboard paths.
- Enhanced UI is turned off while snapping (optional) and turned back on, even after an unexpected quit.

#### Span

- Hold the Span Modifier (Control by default) as well to add every Zone the cursor touches.
- The window snaps to the rectangle that covers all of them.

#### Restore

- Zones records each window's Original Frame at its first Snap and never overwrites it.
- Restore with the Restore shortcut, or by dropping a modifier drag outside the Display's visible frame.
- A Restore target that is off every Display is clamped onto the Display the window overlaps most.

#### Shortcuts

- Control + Option + 1 to 9 sends the focused window to that Zone.
- Control + Option + Right / Left cycles through Zones and wraps.
- Control + Option + R restores, Control + Option + E opens the editor, Control + Option + , opens Settings.
- Every shortcut can be changed or cleared. A shortcut must include Command or Control.
- Clashes with other shortcuts and with other apps are reported in the recorder.

#### Layout editor

- Split (H, V), merge (M), drag or nudge dividers (arrows, Shift + arrows), undo and redo.
- Template picker, per-Layout Margin and Gap sliders, and a Display picker.
- Save (Command + S) and Assign to Display (Command + Shift + A). Edits reach the running app without a relaunch.
- Toolbar controls carry VoiceOver labels, and editor messages are announced to VoiceOver.

#### Layouts and templates

- 12 built-in Layouts: Columns and Rows (2 to 5), Grid (4 or 9), Priority Grid (3), Focus (1).
- Priority Grid is the default for a Display with no Assignment.
- Custom Layouts as split trees in `~/Library/Application Support/Zones/layouts.json`.
- Atomic writes, versioned documents, migration with a backup, and quarantine of unreadable files.
- Import (Merge or Replace) and export of Layouts and Assignments as JSON.

#### Settings panes

- General: permission and event tap status, Re-run onboarding, Modifier keys, Launch at Login.
- Layouts: Assignments per Display, custom Layouts, import and export.
- Shortcuts: one recorder per action.
- Appearance: fill color, opacity, default Margin and Gap, Enhanced UI policy.
- Exclusions: apps that are never snapped. System agents such as the Dock are always excluded.
- About: version, build, signing identity, license.

#### Onboarding and permission

- Accessibility is the only permission. No Screen Recording, no network.
- Onboarding window with a direct link to Privacy & Security > Accessibility and a cheat sheet page.
- Permission loss is detected while running. The menu bar icon gets a red dot and window shortcuts are removed.
- Quit and Reopen is offered only when a relaunch can actually help.
- On a login launch no window opens; the red dot and a Grant Accessibility menu item stand in.

#### Multi-Display topology

- One Assignment per Display, keyed by the Display's UUID.
- Display changes are debounced. Panels resize and an active drag re-arms on the new topology.
- A disconnected Display keeps its Assignment, which can be copied or forgotten in Settings > Layouts.
- Mirrored Displays share the master Display's key.

#### Diagnostics

- A diagnostics report (version, signing identity, macOS, permission, tap, Displays, Assignments,
  Preferences and a ring of recent events). It never contains window titles.
- The report is shown as a preview before it can be copied.
- Events go to the unified log under one category per module.

#### Developer tooling

- `scripts/dev-cert.sh` creates a stable "Zones Dev" signing identity so the Accessibility grant survives rebuilds.
- `scripts/merge-ticket.sh` gate: build, test and xcodebuild before every merge.
- `scripts/release.sh` builds a universal app and an ad-hoc signed DMG; a Homebrew cask lives in `Casks/`.
- CI runs on pull requests to `main` and on manual dispatch only.

### Known issues

- Live drag, Snap and overlay behavior has not been verified on real hardware.
- After an update of an ad-hoc build, System Settings can show Zones as on while the new copy is not trusted;
  remove Zones from the Accessibility list with the minus button (−) and turn it on again (the onboarding window
  says so after 10 s; T56, user report on 2026-10-24).
- 30 manual acceptance checks (of 169) are pending a human run (see [docs/STATUS.md](docs/STATUS.md)).
- `scripts/dev-cert.sh --harden` must be run once by the user on a keychain made by the older script.
- `scripts/dev-cert.sh` recovery path: when the dev keychain exists but holds no identity, the import step fails
  (T51 review).
- Copy Diagnostics is built and tested, but no menu item or button in the app calls it yet.
- `AXObserverBridge` keeps a dangling refcon after `forget`; `element(at:)` keeps issuing Accessibility calls
  after a timeout; private Accessibility helpers lack `@WindowActor` (T13).
- `EventTapInputSource` streams use unbounded buffers; `reenable()` runs outside the lifecycle lock;
  `start() == .unavailable` emits no tap signal (T23).
- The onboarding window always activates the app when shown, which can steal focus on permission loss (T33).
- After a topology change during a drag, Span Zone numbers come from the old Layout; a number missing from the
  new Layout shrinks the drop rectangle silently (T39 review).

[Unreleased]: https://github.com/wakeupdg/zones/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/wakeupdg/zones/releases/tag/v0.1.0
