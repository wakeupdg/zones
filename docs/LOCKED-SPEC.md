# Zones — Locked Specification

Synthesized from the three persona drafts (power-user, platform, maintainer) and nine critique rounds. The 25 ADRs and CONTEXT.md are authoritative; every conflict below is resolved in their favor, and the few places where research shows an ADR's wording is wrong are recorded under "Challenges to ADRs" in section 8, never applied silently.

## 1. Problem Statement

A person with one or more Displays wants windows to land in predictable rectangles without hand-resizing them. macOS offers nothing between "drag it by hand" and full-screen. Existing tools either tile everything and fight the user, snap only to halves and quarters, demand private APIs that break with every OS update, or ask for Screen Recording and Input Monitoring on top of Accessibility. On real Macs they also fail quietly: the Accessibility grant vanishes after a rebuild or revocation, one hung app freezes the menu bar, Chromium windows animate to the wrong place, a Display unplug scrambles which Layout belongs where, and a 120 Hz Drag Session stutters. FancyZones users want the Windows gesture on the Mac: hold a key while dragging, see the Layout, drop, done; one chord per Zone; a visual editor that takes seconds; the same gesture always doing the same thing, on every Display, for every well-behaved window, never moving a window the user did not touch.

## 2. Solution

Zones is a menu-bar-only app for macOS 14+ that asks for exactly one permission (Accessibility), explains why, and says plainly when it is missing or lost. Each Display has an Assignment to a Layout, chosen from a Template (Columns, Rows, Grid, Priority Grid, Focus) or built in an editor by splitting, merging and resizing Zones and setting Margin and Gap. During a Drag Session, once Zones has confirmed the window is moving and the Activation Modifier (default Shift) is held, a click-through Overlay on every Display shows the active Layout and highlights the Zone under the cursor; holding the Span Modifier (default Control) accumulates Zones into a Span; releasing the mouse with the Activation Modifier still down Snaps the window, reads back the frame the app accepted, and remembers the Original Frame so Restore works. Shortcuts (Control+Option+1..9, arrows, R, E, Comma) send the focused window to Zone N, cycle, Restore, and open the editor and Settings. Exclusions by bundle identifier and automatic skips (sheets, popovers, full-screen windows, Zones itself) keep the wrong windows untouched. Layouts and Assignments are versioned JSON that export and import exactly. Every rule that decides what Zones does is a pure function over value types tested headless; the OS sits behind protocols with fakes; every AX call runs off the main thread with a short timeout so a hung app can never hang Zones.

## 3. Lock invariants

- LI-001 Accessibility is the only TCC permission Zones ever requests; Zones never requests Screen Recording or Input Monitoring (ADR-0020).
- LI-002 Zones uses no private API: public Accessibility, CoreGraphics window list, AppKit and Carbon hotkey APIs only; no SkyLight or CGS symbols (ADR-0001).
- LI-003 Zones never reads a window title, window name or owner name; windows are matched by pid and frame, and no title is ever logged (ADR-0020).
- LI-004 A Layout is a binary split tree whose every leaf is a Zone; the Zones tile the Layout rectangle (the Display's visible frame, less the Layout's surround, which is 0 for every Template but Focus) with no gaps and no overlaps before Margin and Gap are applied (ADR-0003).
- LI-005 Zone Numbers are derived by sorting Zones by top edge then left edge and are never stored (ADR-0004).
- LI-006 A Snap moves only the window being dragged or the focused window named by a shortcut; it never moves any other window, and any number of windows may occupy one Zone (ADR-0007).
- LI-007 A Snap happens only if the Activation Modifier is down at mouse-up; releasing it first hides the Overlay and cancels (ADR-0007).
- LI-008 The Overlay is shown only after a window move has been confirmed by frame polling; a click, or a mouse-down without movement, never shows it (ADR-0006).
- LI-009 The highlighted set on the Overlay always equals the set of Zones a mouse-up at that instant would Snap to; the Overlay never lies.
- LI-010 Overlay panels are click-through, never key, never main, one per Display at screenSaver level, created once and reused (ADR-0023).
- LI-011 Every Accessibility read and write runs on the serial WindowActor with a 250 ms per-app messaging timeout; no AX call ever runs on the main actor (ADR-0015).
- LI-012 A frame write is size, then position, then size, then a read-back; the read-back frame is the truth Zones records (ADR-0022).
- LI-013 A full-screen window is never moved or resized; shortcuts and the Overlay do nothing for it, silently (ADR-0014).
- LI-014 Displays are keyed by CGDisplay UUID; only UUID keys are ever persisted (ADR-0012).
- LI-015 Zones never moves a window on its own when a Display is added, removed, resized or mirrored (ADR-0014).
- LI-016 Layouts and Assignments live in versioned JSON documents in Application Support; the export document is the same shape; preferences live in UserDefaults (ADR-0017).
- LI-017 Zones is a menu-bar-only app with no Dock icon, hardened runtime and no App Sandbox, distributed by DMG and Homebrew cask, never through the App Store (ADR-0019).
- LI-018 Zones has zero third-party dependencies; global shortcuts use Carbon registration and every shortcut contains Command or Control (ADR-0010, ADR-0011).
- LI-019 Launch at Login is off by default and registered only by an explicit user action, never at launch.
- LI-020 Every rule that decides what Zones does (numbering, hit test, Span union, Snap plan, exclusion, Drag Session transitions, cycle base, permission state) is a pure function over value types with a headless test; the OS sits behind protocols with scriptable fakes (ADR-0002, ADR-0016).

## 4. User stories

Ids are new and stable. Each story merges every draft story with the same intent; the drafts' own ids are not preserved.

### Shell, permission, onboarding
- US-001 As a user, I want Zones to live only in the menu bar with no Dock icon and no main menu bar, so that it never takes a Dock slot or a Command-Tab position.
- US-002 As a first-time user, I want one onboarding window that explains why Accessibility is needed with a button that opens the exact System Settings pane, so that I grant it in two clicks.
- US-003 As a first-time user, I want Zones to notice the grant within about a second of my flipping the toggle, without a relaunch, so that onboarding dismisses itself and the icon goes live.
- US-004 As a user whose grant was revoked, I want the menu-bar icon badged and the onboarding window back at the first failed call or tap signal, and within five seconds while idle if the heartbeat spike passes, so that I know why dragging stopped and am never promised a signal macOS may not give.
- US-005 As a user who revoked and re-granted, I want the returned window to offer "Open System Settings", and a "Quit and Reopen" button only after Zones has failed to recover the tap three times over ten seconds while the trust probe reads true, so that I am never shown a button that would relaunch into an untrusted app.
- US-006 As a user, I want Zones to request only Accessibility and never Screen Recording or Input Monitoring, so that the privacy footprint is one permission.
- US-007 As a user whose event tap the system disabled, I want Zones to re-enable it quietly under a rate limit, to badge and retry every 30 seconds when the limit is hit, and to treat a nil tap as "not permitted" rather than crash, so that drags recover without a relaunch.
- US-008 As a user launched at login, I want no window to appear on that path, only the badge and a "Grant Accessibility" menu item when the grant is missing, so that login never steals focus.
- US-009 As a developer, I want dev builds signed with a stable self-signed identity, so that rebuilding does not drop the Accessibility grant.
- US-010 As a user updating a Developer ID-signed release, I want the grant to survive, the release script to warn loudly when it falls back to ad-hoc signing, and About and diagnostics to name the signing identity, so that a lost grant after an update explains itself.
- US-011 As a user, I want the General pane to show two status rows (Accessibility granted or not, event tap alive or dead) and the template menu-bar icon to badge for either, so that a dead drag is diagnosable in seconds.
- US-012 As a first-time user, I want onboarding to end with a one-page cheat sheet (hold Shift to see Zones, add Control to Span, Control+Option+N to send) and General to show my two modifiers as key caps, so that I can use Zones before reading anything else.
- US-013 As a user, I want a "Re-run onboarding" action in General that returns Zones to the not-granted flow without touching Layouts or preferences, so that I can recover from a confused permission state.
- US-014 As a user, I want the menu to show the Display under the cursor and its active Layout, an inline Layout picker (Templates named with their Zone counts, then custom Layouts, active one checked), a checkable "Exclude <App Name>" item for the frontmost app, Edit Layouts, Settings, "Grant Accessibility" only when not granted, About and Quit, so that every daily action is one click.
- US-015 As a user, I want the menu to open instantly even while a target app is hung, so that Zones never feels frozen.
- US-016 As a user, I want Settings and the editor to open on the Display under the cursor on the current Space, to become key when opened from the menu and where macOS allows when opened from a shortcut, so that a menu-bar app behaves like a normal one when I ask for a window.
- US-017 As a laptop user who docks lid-closed, I want the first modifier Drag Session after wake to work and the tap, permission and Display list re-checked on wake, so that sleep never leaves a dead tap or stale geometry.
- US-018 As a user, I want Quit to tear down the event tap and panels and restore anything Zones changed in other apps, so that nothing lingers.
- US-019 As a user, I want a Launch at Login toggle that reads the real system status every time Settings appears, is off by default, shows a caption and a button to Login Items when approval is required, and explains when a dev or unsigned build cannot register, so that the toggle never lies.
- US-020 As a user, I want About to show version, build, signing identity, license and the single "inspired by FancyZones" line, so that attribution is honest.

### Drag Session and Overlay
- US-021 As a user, I want to hold the Activation Modifier while dragging any window by its title bar and see the Overlay for the active Layout on every Display, so that I know where a drop will land before I let go.
- US-022 As a user, I want the Overlay to appear only after Zones confirms the window is actually moving, so that a Shift-click on a title bar shows nothing, Snaps nothing and records nothing.
- US-023 As a user, I want the highlighted Zone to be the one under the cursor, not under the window center, so that I can aim a large window with a small motion.
- US-024 As a user, I want releasing the Activation Modifier mid-drag to hide the Overlay and cancel, and the Snap to depend only on whether that modifier is down at mouse-up, so that the rule is one sentence I can trust.
- US-025 As a user, I want to press the Activation Modifier before the mouse-down or after the drag has started, so that both habits work.
- US-026 As a user, I want a plain Drag Session without the modifier to show no Overlay, Snap nothing, Restore nothing and record nothing, and a plain click to cost the target app no Accessibility call at all, so that normal window handling is untouched and a hung app never stalls a click.
- US-027 As a user on a 120 Hz Display, I want the Overlay within one display refresh of the later of (modifier down, move confirmed) and the highlight to follow the cursor on every dragged event, so that the gesture feels native.
- US-028 As a user, I want several windows to coexist in one Zone and a Snap to never move any window but the one I am dragging, so that nothing on my other Displays shifts.
- US-029 As a user, I want Overlay fills translucent above the dragged window and the highlight clearly distinct from idle Zones even at low opacity, so that I can read the window while aiming and still see the target on a bright Display.
- US-030 As a user, I want the Overlay to never take focus, never become key and never intercept clicks, so that the drag completes in the app I started it in and the frontmost app never changes.
- US-031 As a user dragging over a Display whose active Space is a full-screen app, I want the Overlay there only where macOS allows the drop, and a drop on a Display where it cannot land to do nothing, so that the Overlay never shows a target that cannot be hit.
- US-032 As a user, I want Zones to do nothing, silently, when the window I drag is itself full-screen, so that no half-applied resize wrecks a full-screen app.
- US-033 As a user resizing a window by any edge or corner with the Activation Modifier down, I want no Overlay and no Snap, so that a resize is never hijacked.
- US-034 As a user, I want a Drag Session on a background window to work exactly like one on the focused window, so that I never have to click first.
- US-035 As a user, I want a right or middle button press, a second mouse-down or a trackpad glitch during a Drag Session to be ignored, so that state never doubles or cancels by accident.
- US-036 As a user with Caps Lock on, Fn held or the numeric keypad active, I want modifier matching to ignore those flags, so that a Snap is never refused for them.
- US-037 As a multi-Display user, I want the highlight to jump cleanly when the cursor crosses a Display boundary and the Snap to land in the Zone of the Display under the cursor at mouse-up, even while the window still straddles two Displays, so that cross-Display drags are one motion.
- US-038 As a user, I want the Overlay to vanish on mouse-up before Zones talks to the app, so that a slow app never keeps a stale Overlay on screen.
- US-039 As a user whose dragged window is destroyed mid-drag (app quit), I want the Overlay hidden and no write attempted, so that Zones never touches a dead handle.
- US-040 As a user who grabs a title bar and pauses before moving, I want the pause to cost nothing: the Drag Session waits until I move or let go, so that a slow start never disarms Shift.
- US-041 As a user with several same-size windows of one app stacked, I want the one I grabbed to be the one that moves, settled by which candidate actually moved on the first frame sample, and Zones to fail closed when it still cannot tell, so that it never moves the wrong window; four identical terminals must work.
- US-042 As a user with Reduce Motion or Reduce Transparency on, or VoiceOver running, I want the Overlay to draw solid and without fades and to be invisible to VoiceOver, so that my accessibility settings are respected.
- US-043 As a user with a notch or an auto-hiding Dock, I want the Zones of the Layout drawn only inside the Display's visible frame although the panel covers the whole Display, so that no window lands under the menu bar or Dock.
- US-044 As a user whose Display changes resolution, scaling or Dock size mid-drag, I want Zones to re-arm from the new geometry and never abort the drag itself, so that the picture and the drop always agree.
- US-045 As a user who switches Spaces mid-drag, I want Zones to re-assert its panels so the Overlay follows where macOS allows, so that it is never stuck on the old Space.
- US-046 As a user, I want Zone Numbers printed on the Overlay with a contrasting outline independent of fill opacity and the right scale per Display, so that the shortcut legend is always legible.
- US-047 As a user, I want Zones to never consume the modifier or any mouse event (its tap is listen-only), so that an app's own Shift semantics still apply and a content drag never shows the Overlay.
- US-048 As a user dragging an excluded or unmovable window, I want no Overlay at all, so that the feedback is honest and early.

### Snap and Span
- US-049 As a user, I want the window to fill the Zone (less Margin and Gap) on mouse-up with the Activation Modifier down, so that the drop is the commit.
- US-050 As a user, I want the window to land exactly on the rectangle the Overlay drew, to the pixel, on 1x and 2x Displays alike, so that what I see is what I get with no one-pixel seams.
- US-051 As a user dragging a window whose app refuses the requested size, I want Zones to accept the size the app allowed and position the window at the Zone's top-left inside the visible frame, logged, rather than retry or fail, so that placement stays predictable.
- US-052 As a user, I want a Snap to read back the frame the app accepted and treat that as truth, so that cycling and Restore work from reality.
- US-053 As a user snapping across Displays of different sizes, I want the window to land at the Zone's point size on arrival, so that a window from a Retina Display never arrives clamped to its old Display.
- US-054 As a user of Chromium and Electron apps, I want the Snap to land without the slow animated slide or a silently ignored move, so that Chrome feels as crisp as Terminal.
- US-055 As a VoiceOver user, I want Enhanced UI restored after every write even when the write fails, and restored on the next launch for apps a Zones crash left changed, with that bookkeeping never delaying a Snap, so that Zones never degrades VoiceOver elsewhere.
- US-056 As a user snapping a window in a hung app, I want Zones to stop at the first call that times out after one immediate retry, leave that app alone for a short cooldown, then try once more, with the menu bar responsive throughout, so that one bad app costs at most half a second.
- US-057 As a user, I want snapping an already-snapped window to the same Zone to change nothing and leave its Original Frame alone, so that repeated chords are safe.
- US-058 As a user, I want a drop on a Gap or Margin to Snap into the nearest Zone, never Restore, so that an 8-point miss never teleports my window.
- US-059 As a user, I want to hold the Span Modifier during an armed Drag Session and sweep the cursor over several Zones to Snap into their union, so that a window can be two-thirds wide without editing the Layout.
- US-060 As a user, I want the Span to be the bounding rectangle of every accumulated Zone including the Gaps between them (diagonal picks in a 2x2 give the whole Display), and re-sweeping a member to never remove it, so that the result is always one rectangle and a shaky hand cannot shrink it.
- US-061 As a user, I want the accumulating Span highlighted as one rectangle that is exactly what a drop would give me, so that the Overlay never lies.
- US-062 As a user, I want releasing the Span Modifier to freeze the accumulated Span and re-pressing it to keep adding to the same set, with releasing the Activation Modifier as the one way to start over, so that a key bounce never throws away a sweep and a drop never needs three fingers.
- US-063 As a multi-Display user, I want a Span scoped to one Display and suspended, not cleared, while my cursor is elsewhere (drawn dimmer on its Display, with a drop elsewhere using the Zone under the cursor), resuming when I return, so that skimming a seam never loses my sweep.
- US-064 As a user who holds both modifiers before the drag starts, I want the Overlay armed and the Span begun with the Zone under the cursor at the arming sample, so that key order never matters.
- US-065 As a user, I want to pick the Activation Modifier and Span Modifier from Shift, Control, Option and Command, with the two forced to differ, so that the gesture cannot be made ambiguous.
- US-066 As a user of the Focus Template, I want it to be exactly one Zone, Zone Number 1, with a drop anywhere on that Display landing in it, so that "Focus" means one place and one chord.
- US-067 As a user, I want Zones' own work between mouse-up and the first write to the app to be negligible, so that on a responsive app the window is in place as the button comes up.

### Restore and Original Frame
- US-068 As a user, I want Zones to capture a window's Original Frame the first time it Snaps (the frame before I grabbed it on the mouse path, the frame before the write on the keyboard path) and never overwrite it on later Snaps, so that Restore returns to where I started.
- US-069 As a user, I want a Restore shortcut (default Control+Option+R) that returns the focused window to its Original Frame, so that I can undo a Snap from the keyboard.
- US-070 As a user, I want an Activation-Modifier drag that ends outside the Display's visible frame (menu bar or Dock strip) to Restore, with the Overlay staying up, the highlight cleared and every fill dimmed only when an Original Frame exists, so that the mouse path to Restore is discoverable and the cue never lies.
- US-071 As a user, I want Restore to do nothing silently when the window was never snapped or is full-screen, so that the shortcut is safe anywhere.
- US-072 As a user, I want the Original Frame forgotten when the window closes, when its app quits and on a successful Restore, so that Snap, Restore, hand-move, Snap, Restore returns the hand-placed frame.
- US-073 As a user, I want Restore after a Span to work exactly as after a Snap, so that the two gestures share one memory.
- US-074 As a user whose Original Frame is now off every Display, I want Restore to clamp it into the visible frame of the Display the window currently occupies, so that the window never vanishes or jumps Displays.
- US-075 As a user who places windows by chord only, I want the first "send to Zone N" to capture the Original Frame, so that Restore works for keyboard-only placement.

### Shortcuts
- US-076 As a user, I want Control+Option+1 through 9 to send the focused window to Zone N on the Display it is on, so that a window is placed with one chord.
- US-077 As a user, I want Zone Numbers to read row by row from the top-left, to be printed on the Overlay, and to be recomputed after every edit, so that labels and shortcuts always agree.
- US-078 As a user, I want Control+Option+Right and Left to cycle the focused window through the Zones of its Display with wrap, starting from the Zone Zones last sent it to while it has not moved, else from the Zone it overlaps most (a Span continues after its highest member or before its lowest), and from Zone 1 or the last Zone when it matches none, so that the first press is always defined.
- US-079 As a user, I want a "send to Zone N" where N exceeds the Zone count to do nothing, silently, so that a muscle-memory chord is harmless.
- US-080 As a user, I want every shortcut to include Command or Control and never be Option-only, so that shortcuts work on macOS 15 and do not shadow typing.
- US-081 As a user, I want a recorder that shows each shortcut as a chord, lets me press a new one, refuses a chord already bound to another Zones action, and warns (not blocks) for Command-only, Command+Shift-only, and Control-only chords with an arrow or digit, so that collisions are caught without a list that rots per release.
- US-082 As a user, I want a registration failure (chord taken by another app) shown inline with the previous chord left active, so that a dead chord is diagnosable and nothing is lost.
- US-083 As a user, I want the editor and Settings shortcuts to need no permission, and the window shortcuts to need Accessibility (never the mouse tap) and to be registered only while it is granted, so that I can always reach Settings and no chord is swallowed from other apps for nothing.
- US-084 As a user, I want Control+Option+E to open the editor on the Display the cursor is on and Control+Option+Comma to open Settings, so that both are one chord away.
- US-085 As a user, I want shortcuts to act on the focused window of the frontmost app and to do nothing, with one log line, when that window is excluded, full-screen or unmovable, so that the keyboard path obeys the mouse path's rules.
- US-086 As a user, I want clearing a shortcut to leave that action unbound rather than reverting to the default, so that I can free a chord I need elsewhere.
- US-087 As a user, I want a window shortcut pressed during a Drag Session ignored with one log line, and a shortcut re-recorded during a Drag Session applied after it ends, so that Zones never writes a frame while macOS is moving the same window.
- US-088 As a user, I want a modifier, shortcut or Appearance change made in Settings to take effect for the next Drag Session without relaunch and never mid-session, so that tuning is a tight loop that cannot race a drag.

### Layouts, Templates, Displays
- US-089 As a user, I want Templates for Columns and Rows (2 to 5), Grid (2x2, 3x3), Priority Grid (wide center) and Focus, so that the common cases take zero editing.
- US-090 As a user, I want any Display without an Assignment, including one never seen before, to use Priority Grid, so that Zones is useful before I configure anything.
- US-091 As a user, I want Templates read-only, Duplicate to create a custom Layout from one, renaming, and deletion of an assigned Layout blocked until I pick a replacement, so that built-ins are a known starting point and no Display ends up with a dangling Assignment.
- US-092 As a user, I want every Layout to tile the Display with no gaps and no overlaps, with Margin and Gap applied afterward and geometry stored as fractions, so that one Layout fits a 4K and a 1080p Display without dead spots.
- US-093 As a user, I want Margin and Gap in points per Layout, with Appearance holding the defaults that Templates and new custom Layouts use and a custom Layout's own values overriding them, so that one slider sets my house style and one Layout can still differ.
- US-094 As a multi-Display user, I want each Display to have its own Assignment that survives unplug and replug, so that my dock-station Display gets its Layout back without re-assigning.
- US-095 As a user who removes or adds a Display, I want Zones to move no windows and keep every Assignment, so that topology changes are calm.
- US-096 As a user, I want the Layouts pane to list attached Displays with name, resolution and Assignment, and disconnected Displays with "Copy Assignment to <attached Display>" and "Forget", so that a second desk or a changed identifier is handled by me, not by a guess.
- US-097 As a user with "Displays have separate Spaces" off, I want a one-time Settings note recommending it on, so that I understand why windows may straddle Displays.
- US-098 As a user who mirrors Displays, I want the mirror set treated as one Display keyed by the mirror master, with a Layout picked while mirroring kept under that key and each Display resuming its own Assignment on unmirror, so that a presentation never rewrites my desk.
- US-099 As a user with two identical Displays, I want each to keep its own Assignment when the hardware gives distinct identifiers, and otherwise to pick a Layout for each for this session with the Layouts pane saying it will not be saved, so that identical hardware is never silently conflated nor locked to the default.
- US-100 As a user whose Display briefly reports no identifier mid-reconfiguration, I want Zones to retry on a short timer and never persist a bogus Assignment, so that my Assignments stay clean.
- US-101 As a user who changes resolution or scaling, I want Zones recomputed from fractions and the panels resized, with a reconfiguration storm coalesced into one update, so that the Layout still tiles the Display exactly.
- US-102 As a user on the road, I want to edit the Layout assigned to my disconnected desk Display at its last known size and scale, so that I can prepare Layouts before I dock.
- US-103 As a maintainer, I want built-in Layouts to carry deterministic identifiers derived from Template name and count, generated at load and never persisted, so that an Assignment can reference a Template.

### Layout editor
- US-104 As a user, I want the editor to open on the Display under the cursor as a resizable window defaulting to that Display's visible frame, drawing the Zones at real scale over a translucent backdrop, so that what I design is what the Overlay will show and I still see my windows.
- US-105 As a user, I want to select a Zone and split it horizontally or vertically with one key (H or V), so that a three-column Layout takes three keystrokes.
- US-106 As a user, I want a dragged divider to snap to halves, thirds, quarters of its parent and to collinear dividers (free drag with Option), and arrow keys to nudge the selected divider one point (ten with Shift), so that alignment is instant without a numeric field.
- US-107 As a user, I want to merge two sibling Zones with one key (M) and to be told why a merge is not possible with a hint at the split order that gives the shape I want, so that I can undo a split and learn the rules fast.
- US-108 As a user, I want unlimited undo and redo in the editor, so that experiments are free.
- US-109 As a user, I want Margin and Gap sliders with the result shown live on the Display, so that spacing is tuned by eye.
- US-110 As a user, I want Zone Numbers drawn in the editor as they will appear on the Overlay, updating as I split and merge, so that I can plan chords while designing.
- US-111 As a user, I want to switch the Display being edited from inside the editor (including a disconnected Display), prompted first when I have unsaved changes, so that I fix every Layout without reopening it.
- US-112 As a user, I want an Assign action (an editor button and its key equivalent Command-Shift-A) that assigns the Layout being edited to the Display being edited in one click, so that the edit-assign loop is tight.
- US-113 As a user, I want the editor to refuse a ratio that would leave a Zone under one twelfth of the Layout on either axis and to warn when a Zone resolves under 120 by 80 points on the current Display, so that slivers are impossible and tiny Zones are visible before I save.
- US-114 As a user, I want Save and Close bound to shortcuts, Save to be the only moment the live Layout changes, and Cancel to discard the draft, so that experiments can never leak into a Drag Session.
- US-115 As a user building a 4x3, I want Zones beyond nine badged "no chord" and never refused, and the editor to refuse leaving fewer than one Zone, so that I know which Zones are mouse-only.
- US-116 As a user, I want a Template picker inside the editor that generates any Template for a chosen count into the draft, so that I rarely start from scratch.

### Appearance
- US-117 As a user, I want to pick the Zone fill color and opacity with a live sample that says which Layouts use the default Margin and Gap, so that the Overlay is visible on both light and dark wallpapers.

### Exclusions
- US-118 As a user, I want to exclude an app by picking it from running apps or from a file picker, keyed by bundle identifier with the identifier shown beside the name, so that my floating note app never snaps and same-named apps are distinguishable.
- US-119 As a user, I want sheets, popovers, system dialogs, non-standard windows, windows whose position cannot be set and Zones' own windows skipped automatically, and a fixed-size window placed at the Zone's top-left without resizing, so that a Save dialog is never snapped and Calculator still lands.

### Import, export, persistence
- US-120 As a user, I want to export all Layouts and Assignments, or one Layout, to a JSON document of the one shape Zones persists with a version field, so that I can keep them in my dotfiles.
- US-121 As a user, I want import to offer one choice for the whole file, Merge (keep mine, rename theirs) or Replace (a timestamped backup of both documents written and named first), so that I can both combine and restore a backup without per-item prompts.
- US-122 As a user, I want an import of a newer-version document refused naming both versions, and a data file written by a newer Zones left untouched and reported, so that downgrading never destroys newer data.
- US-123 As a user, I want imported Assignments for Displays I do not have kept dormant and applied when that Display appears, so that moving between two desks is painless.
- US-124 As a user, I want a corrupt data file moved aside with a timestamp, Zones to start with defaults and tell me, so that I never lose the file and never lose the app.
- US-125 As a user, I want every data write synchronous and atomic and an edit on disk before the editor closes, so that a crash never leaves a half file or loses a Save.
- US-126 As a user, I want import to validate every Layout (ratios inside 0..1, tiling, minimum fraction), name the first offending Layout, and change nothing if any part fails, so that a bad file cannot corrupt my Layouts.
- US-127 As a user upgrading, I want older documents migrated with a backup written first, so that an upgrade never loses Layouts.
- US-128 As a user, I want preferences to carry a schema version and a hand-edited bad value to coerce only that field to its default with a one-time notice, so that one typo never wipes my shortcuts and exclusions.

### Reliability and diagnostics
- US-129 As a user filing a bug, I want a "Copy Diagnostics" button that shows the report before copying (version, build, signing identity, macOS, permission and tap state, Displays with identifiers and frames, Assignments, preferences, last 200 events, skip counts grouped by bundle identifier) with no window titles or document names, so that one paste is complete and I see what I share.
- US-130 As a user wondering why a window was ignored, I want every skipped window logged with its reason, so that "it did nothing" is diagnosable.
- US-131 As a laptop user, I want Zones to run no timers while idle except the trust poll while not granted and one five-second health tick while granted, and to poll a window's frame only until its move is confirmed, so that battery life is untouched.
- US-132 As a user, I want Zones to never freeze the menu bar or Overlay regardless of what other apps do, so that it is always quittable.
- US-133 As a user, I want stale window handles dropped when a window is destroyed or its app terminates, with no periodic probe, so that memory and Original Frames stay bounded.

### Maintainer stories (acceptance criteria on module tickets, not user features)
- US-134 As a maintainer, I want every rule to be a pure function over value types, so that I can test it in milliseconds without a GUI.
- US-135 As a maintainer, I want AX, CG window listing, the event tap, Displays, hotkeys, login items, the Overlay and the clock each behind one protocol with one production and one scriptable fake, so that logic tests never touch the OS.
- US-136 As a maintainer, I want one and only one coordinate conversion between AppKit, AX and normalized Layout space, so that a flip bug is fixed in one place.
- US-137 As a maintainer, I want the whole logic suite to run with one command from the repository root and in CI on every ticket branch, so that regressions surface before merge.
- US-138 As a maintainer, I want strict-concurrency-clean code with exactly one documented unchecked-Sendable box (the window handle), so that data races cannot creep in.
- US-139 As a maintainer, I want every OS edge to return a typed result (applied, clamped, refused, timedOut, elementGone, noOp) rather than throw or crash, so that callers must handle each case.
- US-140 As a maintainer, I want golden document fixtures per version with a migration test from each older version and a fixture-hash gate, so that format changes are deliberate.
- US-141 As a maintainer, I want the property-test generator to print the failing seed and the generated Layout, so that I reproduce a failure in one run.
- US-142 As a maintainer, I want each ticket to name the protocol it implements, the fake it ships and the tests it adds, so that a fresh agent can build it alone.
- US-143 As a maintainer, I want a manual checklist for behaviors that need a human or a clean VM, run per release, so that releases verify the same things every time.
- US-144 As a maintainer, I want the app target to contain no `try!`, `as!` or `fatalError(` without a per-line allow marker, to import no AX or CG window-list API, and to hold no logic beyond wiring, enforced by a gate, so that the GUI layer stays thin.
- US-145 As a maintainer, I want the hot path (hit test, Span union, resolve, arm) to allocate nothing per frame and headless budget tests with order-of-magnitude bounds, so that CI never gains a flaky gate and 120 Hz stays smooth.
- US-146 As a maintainer, I want a structured logger with subsystem and category per module and a bounded in-memory ring feeding diagnostics, so that logs are searchable and bounded.

## 5. Acceptance statements

Naming: `swift test --filter Suite.testName` runs one Swift Testing case from the repository root; the app target's tests run through the xcodebuild test step. Named constants referenced here: per-app AX timeout 250 ms, process-wide AX timeout 1 s, unresponsive cooldown 10 s, suspect window 3 s, relaunch gate 3 failures over 10 s, topology debounce 200 ms, re-enable limit 5 per minute, dead-tap retry 30 s, health tick 5 s, trust poll 1 s, frame sample cadence about 60 Hz, candidate cap 4, settle samples 3, minimum Zone fraction 1/12, usable size 120x80 pt, divider snap radius 6 pt, Focus surround 0.2 per side, surround maximum 0.45, ring 200 events, frame tolerance 1 pt, cycle match tolerance 2 pt.

### Shell, permission, onboarding
### AC-001 (auto) — Menu-bar only
Statement: The built app's Info.plist has LSUIElement equal to true and declares no NSMainNibFile or main storyboard.
Covers: US-001
Verify: `defaults read` on the built bundle's Info.plist prints `LSUIElement = 1` and no main-interface key.
### AC-002 (auto) — Hardened runtime, no sandbox
Statement: The built app is signed with the hardened runtime flag and carries no `com.apple.security.app-sandbox` entitlement.
Covers: US-001
Verify: `codesign -dv --entitlements :-` on the built app shows `flags=0x10000(runtime)` and the entitlements XML contains no app-sandbox key.
### AC-003 (auto) — Only Accessibility, no private symbols
Statement: The app binary links none of CGRequestScreenCaptureAccess, CGPreflightScreenCaptureAccess, CGPreflightListenEventAccess, CGRequestListenEventAccess, IOHIDRequestAccess, IOHIDCheckAccess, and no undefined symbol beginning with `CGS` or `SLS`; Info.plist has no NSScreenCaptureUsageDescription or NSInputMonitoringUsageDescription.
Covers: US-006
Verify: `nm -u` on the built executable piped through grep for those names returns zero lines; `plutil -p` on Info.plist shows neither key.
### AC-004 (manual) — Onboarding window
Statement: On a clean user account, first launch shows exactly one window whose button opens System Settings at Privacy & Security > Accessibility.
Covers: US-002
Verify: Launch on a clean account; count windows (1); click the button; confirm the Accessibility pane is frontmost.
### AC-005 (manual) — Grant noticed without relaunch
Statement: Flipping the Accessibility toggle on dismisses the onboarding window within 1.5 s and the menu-bar icon loses its badge, with no relaunch.
Covers: US-003
Verify: Start a stopwatch at the toggle; the window closes under 1.5 s; the badge is gone; the process id is unchanged.
### AC-006 (auto) — Poll schedule per permission state
Statement: With a fake Clock, state notGranted schedules exactly one trust poll every 1 s, state granted schedules exactly one health tick every 5 s and no trust poll, and the first true probe emits dismissOnboarding and startTap in that order.
Covers: US-003, US-131
Verify: `swift test --filter PermissionMachineTests.pollScheduleMatchesState`.
### AC-007 (auto) — Revocation via runtime signals
Statement: Given granted, an apiDisabled result from any AX call or a nil tap moves to suspect; a successful tap recreation plus one trivial AX read returns to granted; otherwise after 3 s on the Clock the state is revoked and the effects are badge, showOnboarding, unregisterWindowHotkeys and drainEnhancedUI.
Covers: US-004
Verify: `swift test --filter PermissionMachineTests.suspectResolvesToGrantedOrRevoked`.
### AC-008 (auto) — Relaunch gate
Statement: In revoked with the probe reading true, three failed tap recreations over 10 s on the Clock move to needsRelaunch, which alone offers "Quit and Reopen"; with the probe reading false the state stays revoked indefinitely and never offers the button; a successful recreation from either state returns to granted.
Covers: US-005
Verify: `swift test --filter PermissionMachineTests.relaunchOnlyAfterGateWithProbeTrue`.
### AC-009 (manual) — Revocation on a real Mac
Statement: Revoking Accessibility while Zones idles badges the icon at the next Drag Session or within 5 s when the heartbeat is enabled, and the onboarding window returns; the probe's value after revocation is recorded.
Covers: US-004
Verify: Revoke in System Settings; note time to badge; open the diagnostics report and record the probe field.
### AC-010 (manual) — Re-grant recovery
Statement: Re-granting the toggle either recovers dragging in place within 3 s or shows "Quit and Reopen" after about 10 s, and pressing it yields a trusted app with no onboarding.
Covers: US-005
Verify: Re-grant; drag with the modifier; if dead, wait for the button, press it, confirm the relaunched app snaps.
### AC-011 (auto) — Tap re-enable rate limit
Statement: Five tap-disabled events within 60 s each produce a re-enable call; the sixth produces tapLost immediately with a dead-tap retry scheduled at 30 s; a nil tap on creation yields tapUnavailable and no crash.
Covers: US-007
Verify: `swift test --filter InputSourceTests.reenableRateLimitThenTapLost` and `InputSourceTests.nilTapReportsUnavailable`.
### AC-012 (auto) — Launched-at-login path
Statement: With the launched-as-login-item flag set, state granted emits no window effect and state notGranted emits only badge and a "Grant Accessibility" menu item.
Covers: US-008
Verify: `swift test --filter AppLaunchTests.loginLaunchShowsNoWindow`.
### AC-013 (auto) — Stable dev signing
Statement: The dev build's designated requirement names identifier com.dganesh.zones and the "Zones Dev" certificate and contains no cdhash term.
Covers: US-009
Verify: `codesign -d -r-` on the dev build prints a requirement containing `identifier "com.dganesh.zones"` and not containing `cdhash`.
### AC-014 (auto) — Ad-hoc release warning
Statement: `scripts/release.sh --dry-run` (every release step except signing, notarization and DMG creation) run with ZONES_SIGN_IDENTITY unset prints exactly one line containing "ad-hoc" to stderr and exits 0; the same command with ZONES_SIGN_IDENTITY set prints no such line.
Covers: US-010
Verify: `env -u ZONES_SIGN_IDENTITY scripts/release.sh --dry-run 2>&1 >/dev/null | grep -c ad-hoc` prints `1`; `ZONES_SIGN_IDENTITY="Developer ID Application: Example" scripts/release.sh --dry-run 2>&1 >/dev/null | grep -c ad-hoc` prints `0`.
### AC-015 (auto) — Signing identity in the report
Statement: The diagnostics report contains a `signingIdentity` line whose value is the identity read from the running bundle, or "ad-hoc".
Covers: US-010, US-020, US-129
Verify: `swift test --filter DiagnosticsTests.reportNamesSigningIdentity`.
### AC-016 (auto) — Menu model
Statement: Given cursor on Display B assigned "Columns 3" and frontmost app excluded, the menu model is, in order: header "<B name> — Columns 3" (disabled), radio group of Templates named with counts then custom Layouts with "Columns 3" checked, checkable "Exclude <App Name>" checked, Edit Layouts, Settings, "Grant Accessibility" only when state is not granted, About, Quit.
Covers: US-014
Verify: `swift test --filter MenuModelTests.orderAndStateForDisplayUnderCursor`.
### AC-017 (auto) — Menu never waits on the WindowActor
Statement: Building the menu model with a fake WindowActor that never returns completes and records zero actor calls.
Covers: US-015
Verify: `swift test --filter MenuModelTests.buildsWithoutActorCalls`.
### AC-018 (auto) — Status item state
Statement: The status item model is unbadged only when permission is granted and the tap is enabled, badged in revoked, needsRelaunch and dead-tap, and its image is a template image.
Covers: US-011
Verify: `swift test --filter StatusItemModelTests.badgeTable`.
### AC-019 (auto) — General status rows
Statement: The General pane model exposes exactly two status rows, "Accessibility: Granted|Not granted" and "Event tap: Alive|Dead", derived from the permission and tap states.
Covers: US-011
Verify: `swift test --filter GeneralPaneModelTests.statusRows`.
### AC-020 (manual) — Cheat sheet and key caps
Statement: The last onboarding page lists the three gestures; changing the Activation Modifier to Command in General redraws the key cap to the Command glyph.
Covers: US-012
Verify: Walk onboarding to its last page; change the modifier; observe the key cap.
### AC-021 (auto) — Re-run onboarding
Statement: The re-onboard action from granted moves to notGranted with showOnboarding and leaves the layouts, assignments and preferences stores untouched.
Covers: US-013
Verify: `swift test --filter PermissionMachineTests.reonboardLeavesStoresUntouched`.
### AC-022 (auto) — Window placement
Statement: With the cursor on Display B, the Settings window frame is centered in B's visible frame and the editor window's default frame equals B's visible frame; both windows carry the resizable style mask.
Covers: US-016, US-104
Verify: `swift test --filter WindowPlacementTests.opensOnCursorDisplay`.
### AC-023 (manual) — Key status
Statement: Settings opened from the menu becomes key on the current Space (typing reaches it); opened from Control+Option+Comma with another app frontmost it orders front on the current Space in every case, and becomes key on each macOS version where SPK-014 recorded that a Carbon hotkey handler may take key status.
Covers: US-016
Verify: On macOS 14 and 15, open Settings from the menu and type (text lands); then with TextEdit frontmost press Control+Option+Comma: the Settings window is frontmost on the current Space, and typing reaches it exactly when SPK-014's table says it should for that OS.
### AC-024 (auto) — Wake handling
Statement: A wake event in any Drag Session state yields idle with hideOverlay; the permission machine on wake emits revalidateTap, one probe, forceTopologySnapshot and orderPanelsOut.
Covers: US-017
Verify: `swift test --filter DragSessionReducerTests.wakeEndsSession` and `PermissionMachineTests.wakeEffects`.
### AC-025 (manual) — Wake on a docked Mac
Statement: After lid-closed sleep on an external Display, the first modifier Drag Session after wake shows the Overlay and Snaps.
Covers: US-017
Verify: Sleep lid-closed, wake, Shift-drag a window; observe Overlay and Snap.
### AC-026 (auto) — Quit sequence
Statement: Quit emits disableTap, invalidateTap, orderPanelsOut, drainEnhancedUI and removeRecoveryRecord in that order.
Covers: US-018
Verify: `swift test --filter AppLifecycleTests.quitEffectsInOrder`.
### AC-027 (auto) — Login toggle derivation
Statement: The toggle is on only for status enabled; requiresApproval and notFound show it off with the caption and the Login Items button; turning on from notFound calls register; an invalidSignature error shows the signed-release caption; no register call happens at launch.
Covers: US-019
Verify: `swift test --filter LoginItemToggleTests.derivationTable`.
### AC-028 (manual) — Login item on a clean account
Statement: From a signed copy in Applications on a clean account, turning the toggle on yields status enabled and Zones launches at next login with no window; disabling it in System Settings yields requiresApproval or notFound (recorded).
Covers: US-019, US-008
Verify: Perform the sequence; record each status; log in again and confirm badge-only behavior.
### AC-029 (auto) — About model
Statement: The About pane model exposes version and build read from the bundle, the same signingIdentity value as the diagnostics report (AC-015), the license string "MIT" and exactly one attribution line containing "FancyZones".
Covers: US-020
Verify: `swift test --filter AboutModelTests.fieldsAndSingleAttributionLine`.
### AC-030 (manual) — About pane on screen
Statement: Opening About from the menu shows one window with the five items of AC-029 legible in light and dark appearance, and the attribution line reads "inspired by FancyZones".
Covers: US-020
Verify: Open About in light and in dark appearance; read the five items; count lines containing "FancyZones" (1).

### Drag Session and Overlay
### AC-031 (auto) — Modifier first arms after confirmed move
Statement: Events flagsChanged(Shift), mouseDown, dragged, frameSample(origin moved, size equal) produce state armed and one showOverlay effect covering every Display in the snapshot.
Covers: US-021, US-025
Verify: `swift test --filter DragSessionReducerTests.modifierFirstArmsAfterMove`.
### AC-032 (auto) — A click costs nothing
Statement: mouseDown then mouseUp with no dragged event requests no frame sample, emits no effect and leaves the registry unchanged.
Covers: US-022, US-026
Verify: `swift test --filter DragSessionReducerTests.clickRequestsNoSample`.
### AC-033 (auto) — Overlay only after move
Statement: With Shift down, a frame sample equal to the mouse-down frame emits no showOverlay; the first sample whose origin differs emits showOverlay in that same step.
Covers: US-022, US-027
Verify: `swift test --filter DragSessionReducerTests.overlayOnlyAfterMovedSample`.
### AC-034 (auto) — Highlight under cursor
Statement: In armed, a dragged event at a point inside Zone 3 while the window center lies in Zone 2 emits updateHighlight({3}).
Covers: US-023
Verify: `swift test --filter DragSessionReducerTests.highlightFollowsCursorNotWindow`.
### AC-035 (auto) — Modifier release cancels
Statement: In armed, flagsChanged without the Activation Modifier yields moving with hideOverlay and an empty Span; a following mouseUp emits neither snap nor restore.
Covers: US-024
Verify: `swift test --filter DragSessionReducerTests.modifierReleaseCancels`.
### AC-036 (auto) — Snap keyed on mouse-up flags
Statement: mouseUp in armed with flags containing the Activation Modifier emits snap; mouseUp whose flags lack it emits nothing.
Covers: US-024
Verify: `swift test --filter DragSessionReducerTests.snapOnlyWithModifierAtMouseUp`.
### AC-037 (auto) — Modifier late
Statement: mouseDown, dragged, moved sample, then flagsChanged(Shift) yields armed with showOverlay.
Covers: US-025
Verify: `swift test --filter DragSessionReducerTests.modifierLateArms`.
### AC-038 (auto) — Plain drag records nothing
Statement: moving plus mouseUp yields idle with no snap, no restore and no registry write.
Covers: US-026
Verify: `swift test --filter DragSessionReducerTests.plainDragIsInert`.
### AC-039 (auto) — Hot-path budgets
Statement: hitTest, spanRect, resolve, grid and Overlay arm allocate zero bytes after warm-up on a 9-Zone Layout, and the reducer processes 10,000 dragged events in under 2 s.
Covers: US-027, US-067, US-145
Verify: `swift test --filter BudgetTests`.
### AC-040 (manual) — 120 Hz pacing
Statement: In Instruments on a 120 Hz Display, each highlight update costs under 2 ms on the main actor and the Overlay appears on the display refresh after arm.
Covers: US-027
Verify: Record a Shift-drag with Instruments; read per-event main-actor time and arm latency.
### AC-041 (auto) — Snap touches one window
Statement: Executing a snap plan issues frame writes only to the plan's handle; the fake call log shows no call for any other handle.
Covers: US-028
Verify: `swift test --filter SnapServiceTests.writesOnlyTargetHandle`.
### AC-042 (auto) — Fill and highlight styles
Statement: Overlay fill alpha equals the Appearance opacity; at opacity 0.10 the highlight style differs from the idle style by at least 0.25 alpha or a distinct color.
Covers: US-029
Verify: `swift test --filter OverlayModelTests.highlightDistinctAtLowOpacity`.
### AC-043 (auto) — Panel configuration
Statement: An overlay panel reports ignoresMouseEvents true, canBecomeKey false, canBecomeMain false, level screenSaver, hasShadow false, clear background, and collection behavior containing canJoinAllSpaces, fullScreenAuxiliary, stationary and ignoresCycle.
Covers: US-030
Verify: xcodebuild test `OverlayPanelTests.configuration`.
### AC-044 (manual) — Drag uninterrupted
Statement: During an armed Drag Session the frontmost app pid and key window are unchanged, and a CGWindowList probe shows the Zones panels at layer 1000 only while armed.
Covers: US-030
Verify: Run the probe script during and after a Shift-drag; compare frontmost pid and key window before and after.
### AC-045 (auto) — Displays outside the arm snapshot
Statement: With Display C excluded from the arm snapshot, mouseUp over C yields idle with one log effect and neither snap nor restore.
Covers: US-031
Verify: `swift test --filter DragSessionReducerTests.dropOutsideSnapshotIsNoOp`.
### AC-046 (manual) — Full-screen Space Display
Statement: Dragging a window toward a Display whose active Space is full-screen shows the Overlay there only if the drop is possible, and a drop where it is impossible leaves the window where macOS puts it with no Restore.
Covers: US-031, US-045
Verify: Put Safari full-screen on Display 2; Shift-drag from Display 1; record Overlay visibility and drop result (SPK-002).
### AC-047 (auto) — Full-screen and skipped windows never arm
Statement: A first moved sample whose phase-2 facts report fullScreen, sheetOrPopover, nonStandardSubrole or positionNotSettable yields idle with skip logged, polling stopped and no showOverlay.
Covers: US-032, US-048
Verify: `swift test --filter DragSessionReducerTests.phaseTwoFailureEndsPress`.
### AC-048 (auto) — Resize is never a session
Statement: For each of the eight edges and corners, a sample whose size differs by more than 1 pt yields idle, including the top-left resize that also changes the origin.
Covers: US-033
Verify: `swift test --filter DragSessionReducerTests.resizeFromEveryEdgeEndsSession`.
### AC-049 (auto) — Background window
Statement: A candidate whose pid is not the frontmost app passes phase 1 and arms exactly as a frontmost one; the reducer input carries no focus flag.
Covers: US-034
Verify: `swift test --filter DragSessionReducerTests.backgroundWindowArms`.
### AC-050 (auto) — Stray buttons and presses ignored
Statement: The input source emits no event for right or middle buttons, and a mouseDown in any state but idle leaves state and effects unchanged.
Covers: US-035
Verify: `swift test --filter InputSourceTests.otherButtonsFiltered` and `DragSessionReducerTests.secondMouseDownIgnored`.
### AC-051 (auto) — Modifier masking
Statement: Flags containing Shift plus Caps Lock, Fn and numeric-pad bits match an Activation Modifier of Shift; flags containing only Caps Lock do not.
Covers: US-036
Verify: `swift test --filter ModifierMaskTests.ignoresNonModifierBits`.
### AC-052 (auto) — Cross-Display hit and drop
Statement: With the window straddling Displays A and B and the cursor on B, hit testing uses B's Layout and mouseUp emits a snap plan in B's coordinates.
Covers: US-037
Verify: `swift test --filter DragSessionReducerTests.straddlingWindowSnapsOnCursorDisplay`.
### AC-053 (auto) — Hide before write
Statement: The reducer step for mouseUp in armed emits hideOverlay before snap or restore within that single step.
Covers: US-038, US-067
Verify: `swift test --filter DragSessionReducerTests.hideOverlayPrecedesSnap`.
### AC-054 (auto) — Window gone mid-drag
Statement: windowGone in armed yields idle with hideOverlay and no snap effect.
Covers: US-039
Verify: `swift test --filter DragSessionReducerTests.windowGoneHidesOverlay`.
### AC-055 (auto) — Pause keeps the press
Statement: Three unmoved samples keep state pressed; a later moved sample yields moving.
Covers: US-040
Verify: `swift test --filter DragSessionReducerTests.pauseThenMoveStillArms`.
### AC-056 (auto) — Candidate resolution
Statement: Two stacked candidates resolve to the one whose first sample moved; four candidates are read in one batched call per tick; five candidates yield ambiguousMatch before sampling; two movers after three returned samples yield idle; a timed-out sample after its one retry yields idle with skip(unresponsive).
Covers: US-041
Verify: `swift test --filter DragSessionReducerTests.candidateTable`.
### AC-057 (manual) — Four identical terminals
Statement: With four same-size Terminal windows stacked, Shift-dragging any one moves that one and the Overlay appears.
Covers: US-041
Verify: Open four Terminal windows at one size; drag each in turn (SPK-008).
### AC-058 (auto) — Accessibility settings in the model
Statement: With reduceTransparency the Overlay model uses solid fills and draws a suspended Span as an outline; with reduceMotion no animation duration is set; panels and layers report isAccessibilityElement false.
Covers: US-042
Verify: `swift test --filter OverlayModelTests.accessibilityOptions` and xcodebuild test `OverlayPanelTests.notAccessibilityElement`.
### AC-059 (auto) — Zones inside the visible frame
Statement: Every resolved Zone rectangle lies within the Display's visible frame while the panel frame equals the full Display frame, for the 3-Display fixture.
Covers: US-043
Verify: `swift test --filter OverlayModelTests.zonesWithinVisibleFrame`.
### AC-060 (auto) — Topology change mid-session
Statement: topologyChanged in armed yields armed with a new showOverlay from the new snapshot and a re-hit; in pressed or moving it refreshes the snapshot and keeps state.
Covers: US-044, US-101
Verify: `swift test --filter DragSessionReducerTests.topologyChangeRearms`.
### AC-061 (manual) — Resolution change mid-drag
Statement: Changing resolution during an armed Drag Session redraws the Overlay to the new geometry; whether macOS ends the drag itself is recorded.
Covers: US-044
Verify: Shift-drag, change resolution from a second input; observe and record.
### AC-062 (auto) — Space change re-asserts
Statement: spaceChanged in armed emits reassertPanels and a re-hit without leaving armed.
Covers: US-045
Verify: `swift test --filter DragSessionReducerTests.spaceChangeReasserts`.
### AC-063 (auto) — Label model
Statement: Each Zone's label text equals its Zone Number, the label outline contrasts with the fill at ratio 4.5 or better at any opacity, and contentsScale equals the Display scale.
Covers: US-046
Verify: `swift test --filter OverlayModelTests.labelsLegibleAndScaled`.
### AC-064 (manual) — Accessibility on screen
Statement: Labels are readable at 10 percent fill opacity on a white wallpaper; with Reduce Transparency fills are solid; with Reduce Motion nothing fades; VoiceOver announces nothing for the Overlay.
Covers: US-046, US-042
Verify: Set each option in turn and Shift-drag; observe.
### AC-065 (auto) — Listen-only tap configuration
Statement: The tap configuration value used by the production input source is listenOnly with a mask of left mouse down, dragged, up and flagsChanged only.
Covers: US-047
Verify: `swift test --filter InputSourceTests.productionTapIsListenOnly`.
### AC-066 (manual) — Modifier never consumed
Statement: With Zones running, Shift-click multi-selection in Finder and Shift-constrained drags in a drawing app behave as without Zones.
Covers: US-047
Verify: Perform both gestures with Zones running and quit; compare.
### AC-067 (auto) — Excluded at phase 1
Statement: A candidate whose bundle identifier is excluded, whose pid is Zones' own, or whose bundle is a system agent yields skip at mouseDown with no frame sample ever requested and no showOverlay for that press.
Covers: US-048, US-118
Verify: `swift test --filter DragSessionReducerTests.phaseOneSkipBeforeSampling`.

### Snap and Span
### AC-068 (auto) — Overlay and Snap share one geometry
Statement: For the 3-Display fixture at scales 1, 2 and 3, the Snap target rectangle for Zone N equals the Overlay rectangle for Zone N exactly.
Covers: US-049, US-050
Verify: `swift test --filter GridRoundingTests.overlayEqualsSnapTarget`.
### AC-069 (auto) — Divider rounding
Statement: After the grid step every divider lies on a pixel boundary (1 divided by scale), every Gap measures the same whole number of pixels, neighbours share each divider, and a mirror-image tree produces mirror-image pixels, at scales 1, 2 and 3.
Covers: US-050
Verify: `swift test --filter GridRoundingTests.uniformPixelGapsAndSharedDividers`.
### AC-070 (manual) — Cross-scale Snap on screen
Statement: Snapping a window from a 2x Display into a Zone on a 1x Display lands its edges on the Overlay's rectangle with no visible seam, and across three Displays no other window moves.
Covers: US-050, US-053, US-028
Verify: Zoom a screenshot of the landed window and Overlay edges; count moved windows (0).
### AC-071 (auto) — Clamped size placement
Statement: On clamped with accepted size larger than the Zone, exactly one follow-up position write aligns the top-left inside the visible frame and a log effect records the clamp; no further writes follow.
Covers: US-051
Verify: `swift test --filter SnapServiceTests.clampedGetsOneRepositionOnly`.
### AC-072 (auto) — Read-back is truth
Statement: The result of a Snap carries the read-back frame, and the registry's last-Snap record stores that frame, not the requested one.
Covers: US-052
Verify: `swift test --filter SnapServiceTests.resultCarriesReadBackFrame`.
### AC-073 (auto) — Write order
Statement: A Snap issues setSize, setPosition, setSize, readPosition, readSize in that order on the fake element.
Covers: US-053
Verify: `swift test --filter SnapServiceTests.writeOrderSizePositionSize`.
### AC-074 (auto) — Enhanced UI protocol
Statement: Enhanced UI is read first; the off/on pair is skipped when the attribute is absent or already off; otherwise it is set off before the first size write and restored on every path including refused and timedOut.
Covers: US-054, US-055
Verify: `swift test --filter SnapServiceTests.enhancedUIRestoredOnEveryPath`.
### AC-075 (manual) — Electron and VoiceOver
Statement: Snaps in Chrome, VS Code and Slack land without animation; with VoiceOver on, VoiceOver keeps working in those apps after ten Snaps.
Covers: US-054, US-055
Verify: Snap each app ten times with VoiceOver on; observe motion and VoiceOver (SPK-010).
### AC-076 (auto) — Recovery record
Statement: The recovery record is written once per (bundle identifier, pid, launch date) at an app's first touch in a session, after the frame write sequence completes, with the prior Enhanced UI value; a second Snap writes nothing; at launch only entries matching all three fields with prior value on are restored; clean quit deletes the file.
Covers: US-055
Verify: `swift test --filter EnhancedUIRecoveryTests.writeOnceRestoreOnMatch`.
### AC-077 (auto) — Timeout protocol
Statement: A timedOut call is retried once immediately; a second timeout aborts the sequence (only the Enhanced UI restore follows), returns timedOut and marks the pid unresponsive for 10 s on the Clock, during which phase 1 reports skip(unresponsive); after the cooldown exactly one attempt is allowed; the fake's call count is asserted.
Covers: US-056
Verify: `swift test --filter SnapServiceTests.timeoutRetryOnceThenAbort` and `AppHealthTests.cooldownThenOneRetry`.
### AC-078 (manual) — Hung app on a real Mac
Statement: With an app stopped by SIGSTOP: a plain click on its title bar reaches macOS with no Zones AX call (the diagnostics ring shows no event for that pid, and the click-to-highlight time on a 60 fps screen recording is within 50 ms of the same click with Zones quit); an armed Drag Session gives up within 0.5 s of mouse-up; and the Zones menu opens in under 200 ms (12 frames at 60 fps) on every attempt before, during and after the Snap attempt.
Covers: US-056, US-132, US-015
Verify: Screen-record at 60 fps; `kill -STOP` the app; click its title bar (compare frame counts with Zones quit, delta at most 3 frames), Shift-drag it (Overlay hidden to give-up at most 30 frames), open the menu three times (each under 12 frames); `kill -CONT`; inspect the diagnostics ring for the click.
### AC-079 (auto) — Idempotent Snap
Statement: A snap plan whose target equals the current frame within 1 pt returns noOp, issues no write and leaves the registry entry unchanged.
Covers: US-057
Verify: `swift test --filter SnapServiceTests.sameZoneIsNoOp`.
### AC-080 (auto) — Gap and Margin snap to nearest
Statement: hitTest returns nearest(n) for every point inside the visible frame but outside all Zones (minimum edge distance, ties to the lower Zone Number), and the reducer emits snap, never restore, for a nearest hit.
Covers: US-058
Verify: `swift test --filter HitTestTests.gapAndMarginAreNearest` and `DragSessionReducerTests.nearestSnaps`.
### AC-081 (auto) — Span accumulation and union
Statement: Sweeping Zones 1, 2, 3 with the Span Modifier down yields set {1,2,3} whose spanRect is the bounding rectangle including Gaps; {1,4} in a 2x2 yields the whole Layout rectangle; re-sweeping 2 leaves the set unchanged.
Covers: US-059, US-060
Verify: `swift test --filter SpanTests.accumulateAndUnion`.
### AC-082 (auto) — Highlight invariant
Statement: For random event streams, in every armed state the highlighted set equals the set a mouseUp would snap to, and dimAll appears only when the hit is none and hasOriginalFrame is true.
Covers: US-061, US-070
Verify: `swift test --filter ReducerInvariantTests.highlightEqualsDropSet`.
### AC-083 (auto) — Freeze, resume, clear
Statement: Releasing the Span Modifier keeps the set frozen; re-pressing resumes adding; releasing the Activation Modifier clears it.
Covers: US-062
Verify: `swift test --filter SpanTests.freezeResumeClear`.
### AC-084 (auto) — Suspend across a seam
Statement: The cursor leaving the Span's Display marks the set suspended, the highlight becomes the Zone under the cursor and the suspended set is passed in the secondary style; returning resumes; a mouseUp on the other Display snaps to that Zone.
Covers: US-063
Verify: `swift test --filter SpanTests.suspendAndResumeAcrossDisplays`.
### AC-085 (manual) — Seam skim on three Displays
Statement: A three-Zone Span on Display A stays drawn dimmer while the cursor skims Display B, and dropping back on A gives the three-Zone union.
Covers: US-063
Verify: Perform the sweep on a 3-Display desk; observe and drop.
### AC-086 (auto) — Both modifiers first
Statement: With both modifiers down before the move, the arming sample yields armed with the Span containing the Zone under the cursor; arming over a Gap yields an empty Span until the first Zone is entered.
Covers: US-064
Verify: `swift test --filter SpanTests.bothModifiersBeforeMove`.
### AC-087 (auto) — Modifier choice
Statement: Preferences accept only Shift, Control, Option, Command for each modifier and coerce equal modifiers so the Span Modifier differs, with a one-time notice flag set.
Covers: US-065
Verify: `swift test --filter PreferencesTests.modifiersMustDiffer`.
### AC-088 (auto) — Focus Template
Statement: Focus is one leaf with surround 0.2 per side; its only Zone is Zone Number 1 and resolves to the centered 60 percent of the visible frame; hitTest at any point inside the visible frame returns zone(1) or nearest(1).
Covers: US-066
Verify: `swift test --filter TemplateTests.focusIsOneCenteredZone`.

### Restore and Original Frame
### AC-089 (auto) — First-Snap capture
Statement: On the mouse path the registry stores the mouse-down frame of the resolved window; on the keyboard path the pre-write read-back frame; a second applied Snap does not overwrite either.
Covers: US-068, US-075
Verify: `swift test --filter OriginalFrameRegistryTests.firstSnapCapturesPerPath`.
### AC-090 (auto) — Restore command
Statement: Restore with an entry writes the Original Frame through the write protocol and removes the entry on applied or clamped.
Covers: US-069, US-072
Verify: `swift test --filter RestoreTests.writesAndRemovesEntry`.
### AC-091 (auto) — Mouse Restore and dim cue
Statement: A none hit with an Original Frame emits updateHighlight(dimAll) and mouseUp emits restore; without an Original Frame the highlight is cleared, nothing dims and mouseUp emits nothing.
Covers: US-070, US-071
Verify: `swift test --filter DragSessionReducerTests.noneHitDimsOnlyWithOriginalFrame`.
### AC-092 (auto) — Restore no-ops
Statement: Restore on a full-screen focused window or a window with no entry returns noOp(reason) and emits one log line and no write.
Covers: US-071, US-085
Verify: `swift test --filter RestoreTests.noOpReasons`.
### AC-093 (auto) — Forget rules
Statement: Snap, Restore, hand-move, Snap, Restore returns the hand-placed frame; destroyed and app-terminated notifications evict every entry of that pid; elementGone evicts at next touch; no periodic sweep is scheduled.
Covers: US-072, US-133
Verify: `swift test --filter OriginalFrameRegistryTests.forgetRules`.
### AC-094 (auto) — Restore after Span
Statement: A Span Snap and a single-Zone Snap record the same kind of entry and Restore returns the same Original Frame.
Covers: US-073
Verify: `swift test --filter RestoreTests.spanAndSnapShareMemory`.
### AC-095 (auto) — Off-Display clamp
Statement: An Original Frame intersecting no Display is clamped into the visible frame of the Display the window currently overlaps most before the write.
Covers: US-074
Verify: `swift test --filter RestoreTests.clampsOntoOccupiedDisplay`.
### AC-096 (manual) — Restore returns to the pre-grab place
Statement: Shift-dragging a window from the left of a Display into a Zone on the right, then pressing Control+Option+R, puts it back at its left-side position, not under the drop point.
Covers: US-068
Verify: Note the window's position, Snap by drag, Restore, compare.

### Shortcuts
### AC-097 (auto) — Defaults match ADR-0010
Statement: Default shortcuts are Control+Option+1..9 sendToZone, Control+Option+Right and Left cycle, Control+Option+R restore, Control+Option+E openEditor, Control+Option+Comma openSettings.
Covers: US-076, US-084, US-069
Verify: `swift test --filter ShortcutStoreTests.defaultsMatchADR`.
### AC-098 (auto) — Send to Zone N
Statement: sendToZone(3) on a window overlapping Display B most produces a snap plan for B's Zone 3 rectangle from B's current Assignment.
Covers: US-076
Verify: `swift test --filter ShortcutResolverTests.sendToZoneUsesOccupiedDisplay`.
### AC-099 (auto) — Zone numbering property
Statement: For random trees, Zone Numbers are a bijection onto 1..N, ordered by top edge then left edge with epsilon, invariant under frame scaling and Margin and Gap changes, and recomputed after each editor command.
Covers: US-077
Verify: `swift test --filter ZoneNumberingTests.rowMajorBijection`.
### AC-100 (auto) — Cycle table
Statement: With a last-Snap record whose frame matches the read-back within 2 pt, Right continues after its highest Zone and Left before its lowest (Calculator clamped at 3 cycles Right to 4; a Span of 1 and 2 cycles Right to 3); after a hand move the base is the Zone of maximum intersection, ties to the lower number; with no intersection Right starts at 1 and Left at the last Zone; both wrap.
Covers: US-078
Verify: `swift test --filter CycleResolverTests.table`.
### AC-101 (auto) — Zone N beyond count
Statement: sendToZone(7) on a 3-Zone Layout returns noOp(zoneAbsent) with one log line and no write.
Covers: US-079
Verify: `swift test --filter ShortcutResolverTests.absentZoneIsNoOp`.
### AC-102 (auto) — Command or Control required
Statement: The validator rejects any chord lacking both Command and Control, including Option-only and Shift+Option chords, and accepts Control+Option+1.
Covers: US-080
Verify: `swift test --filter ShortcutStoreTests.requiresCommandOrControl`.
### AC-103 (auto) — Recorder states
Statement: A chord bound to another Zones action yields conflict(duplicate); Command-only, Command+Shift-only, and Control-only with an arrow or digit yield warning that can be accepted; Control+Option+5 yields no warning.
Covers: US-081
Verify: `swift test --filter ShortcutStoreTests.recorderStateTable`.
### AC-104 (auto) — Registration failure keeps old chord
Statement: A registration result of inUse yields failed(inUse) and the fake registrar still holds the previous chord for that action.
Covers: US-082
Verify: `swift test --filter ShortcutStoreTests.failureKeepsPreviousChord`.
### AC-105 (auto) — Registration by permission state
Statement: openEditor and openSettings are registered in every permission state; window actions are registered only on entering granted and unregistered on leaving it.
Covers: US-083
Verify: `swift test --filter ShortcutStoreTests.windowHotkeysOnlyWhileGranted`.
### AC-106 (manual) — Shortcuts without the grant
Statement: With Accessibility not granted, Control+Option+E opens the editor and Control+Option+1 reaches other apps (it is not swallowed).
Covers: US-083
Verify: Revoke; press both chords with TextEdit frontmost; observe.
### AC-107 (manual) — Editor and Settings chords
Statement: Control+Option+E opens the editor on the Display under the cursor; Control+Option+Comma opens Settings.
Covers: US-084
Verify: Press each chord with the cursor on Display 2; observe which Display the window appears on.
### AC-108 (auto) — Command path gates
Statement: A window command whose focused window is excluded, full-screen, position-not-settable or absent returns noOp(reason) with one log line and no write.
Covers: US-085
Verify: `swift test --filter ShortcutResolverTests.gateTable`.
### AC-109 (auto) — Cleared shortcut
Statement: Clearing a shortcut leaves the action unbound (not the default) and issues one unregister call.
Covers: US-086
Verify: `swift test --filter ShortcutStoreTests.clearedStaysUnbound`.
### AC-110 (auto) — Dispatch during a Drag Session
Statement: A window command fired while the reducer is not idle is dropped with exactly one log line; a registration diff made then is queued and applied on return to idle.
Covers: US-087
Verify: `swift test --filter ShortcutDispatchTests.droppedAndQueuedDuringSession`.
### AC-111 (auto) — Preference change diff
Statement: Changing one shortcut re-registers only that action; changing the Activation Modifier is read by the reducer at the next mouseDown and not mid-session.
Covers: US-088
Verify: `swift test --filter ShortcutStoreTests.diffReregistersOnlyChanged` and `DragSessionReducerTests.modifierConfigReadAtMouseDown`.

### Layouts, Templates, Displays
### AC-112 (auto) — Template shapes
Statement: Columns and Rows at 2..5 produce that many equal-extent Zones (within epsilon); Grid produces 4 and 9; Priority Grid produces three side-by-side Zones at 25/50/25; Focus produces one; Template names equal the CONTEXT glossary names exactly.
Covers: US-089
Verify: `swift test --filter TemplateTests.countsShapesAndNames`.
### AC-113 (auto) — Default Assignment
Statement: Lookup for a key absent from the Assignments document returns the Priority Grid built-in identifier.
Covers: US-090
Verify: `swift test --filter AssignmentLookupTests.unknownDisplayGetsPriorityGrid`.
### AC-114 (auto) — Built-in identifiers and Duplicate
Statement: Built-in Layout identifiers are identical across two load runs, never appear in the layouts document, and Duplicate yields a fresh identifier, the name "<Template> copy" and explicit Margin and Gap equal to the current defaults.
Covers: US-103, US-091
Verify: `swift test --filter BuiltInLayoutTests.deterministicIdsAndDuplicate`.
### AC-115 (auto) — Delete needs a replacement
Statement: Deleting a Layout referenced by any Assignment without a replacement is refused; with a replacement every referencing Assignment is rewritten in the same transaction.
Covers: US-091
Verify: `swift test --filter LayoutStoreTests.deleteAssignedRequiresReplacement`.
### AC-116 (auto) — Tiling property
Statement: For random trees up to depth 8, leaves tile the Layout rectangle with no positive-area overlap and no gap, every ratio is strictly inside 0..1, every leaf is at least 1/12 on each axis, and with Margin and Gap applied every pair is separated by exactly Gap and the outer edge by exactly Margin on unrounded output.
Covers: US-092
Verify: `swift test --filter LayoutTilingTests.randomTreesTile`.
### AC-117 (auto) — Margin and Gap defaults
Statement: Built-in Layouts are generated with the Appearance default Margin and Gap; changing the defaults regenerates built-ins and leaves custom Layouts unchanged; every Layout on disk carries explicit numeric Margin and Gap.
Covers: US-093
Verify: `swift test --filter LayoutStoreTests.defaultsApplyToBuiltInsOnly`.
### AC-118 (auto) — Topology Assignment rules
Statement: A returning UUID restores its Assignment; a removed Display keeps its Assignment and no move effect is emitted; a new UUID gets the default.
Covers: US-094, US-095
Verify: `swift test --filter TopologyTests.assignmentsSurviveReconnect`.
### AC-119 (manual) — Dock Display replug
Statement: Unplugging and replugging the dock Display restores its Layout and moves no window; two identical Displays of one model each keep their own Assignment or are labelled "not saved".
Covers: US-094, US-095, US-099
Verify: Unplug, replug, Shift-drag to confirm the Layout; count moved windows (0); check the Layouts pane (SPK-012).
### AC-120 (auto) — Layouts pane model
Statement: The pane model lists attached Displays with name, resolution and picker, disconnected Displays with name, last resolution, Assignment, "Copy Assignment to <attached>" and "Forget", and labels unstable keys "not saved".
Covers: US-096, US-099
Verify: `swift test --filter LayoutsPaneModelTests.rows`.
### AC-121 (auto) — Separate Spaces notice
Statement: A snapshot with separateSpaces false sets the one-time notice flag once and never again.
Covers: US-097
Verify: `swift test --filter TopologyTests.separateSpacesNoticeOnce`.
### AC-122 (auto) — Mirror handling
Statement: A snapshot with mirrorOf collapses the group to the master's key; a Layout picked while mirrored is persisted under the master's key; unmirroring restores each member's own Assignment.
Covers: US-098
Verify: `swift test --filter TopologyTests.mirrorKeyedByMaster`.
### AC-123 (auto) — Unstable and nil identifiers
Statement: A nil UUID is retried three times one second apart on the Clock; a late success emits topologyChanged; three failures yield an unstable key that accepts an in-session Assignment, is never encoded, and the document decoder rejects any non-UUID key.
Covers: US-099, US-100
Verify: `swift test --filter TopologyTests.nilUUIDRetryThenUnstable` and `DocumentTests.rejectsNonUUIDKey`.
### AC-124 (auto) — Debounce and resize
Statement: Five reconfiguration callbacks within 200 ms yield one topologyChanged; a resolution change yields Zone rectangles recomputed from fractions and panel frames equal to the new Display frames.
Covers: US-101
Verify: `swift test --filter TopologyTests.stormCoalescesAndResizes`.
### AC-125 (auto) — Disconnected Display editing
Statement: Opening the editor for a disconnected Display resolves the draft against the stored last visible frame and last scale from its Assignment record.
Covers: US-102
Verify: `swift test --filter EditorModelTests.disconnectedDisplayUsesStoredGeometry`.

### Layout editor
### AC-126 (manual) — Editor backdrop
Statement: Control+Option+E opens the editor over a translucent backdrop through which the desktop windows behind it remain visible, drawing the Zones at real scale so that each editor Zone covers the same screen area the Overlay would highlight for it (frame rule: AC-022).
Covers: US-104
Verify: Open the editor over a desk with three visible windows; confirm all three show through the backdrop; Shift-drag a window with the editor still open and compare the Overlay's Zone 1 edges to the editor's Zone 1 edges in a screenshot (equal).
### AC-127 (auto) — Single-key split
Statement: H on a selected leaf splits it side by side at ratio 0.5 and V stacks it; the leaf count rises by one each time.
Covers: US-105
Verify: `swift test --filter EditorCommandTests.splitKeys`.
### AC-128 (auto) — Divider snapping and nudging
Statement: A divider dragged within 6 pt of 1/2, 1/3, 1/4 of its parent or a collinear divider snaps there; with Option it does not; arrows move the selected divider by 1 pt, Shift+arrows by 10 pt, expressed as ratio deltas for the current Display.
Covers: US-106
Verify: `swift test --filter EditorCommandTests.dividerSnapAndNudge`.
### AC-129 (auto) — Merge rules
Statement: M on a leaf whose sibling is a leaf collapses the parent; M on any other pair returns notSiblings with the hint "split the parent the other way first" and leaves the draft unchanged.
Covers: US-107
Verify: `swift test --filter EditorCommandTests.mergeSiblingsOnly`.
### AC-130 (auto) — Undo and redo
Statement: 100 random valid commands followed by 100 undos restore the original draft and 100 redos restore the final draft.
Covers: US-108
Verify: `swift test --filter EditorCommandTests.undoRedoRoundTrip`.
### AC-131 (auto) — Live Margin and Gap
Statement: setMargin and setGap commands change the draft and the preview model's resolved rectangles in the same step.
Covers: US-109
Verify: `swift test --filter EditorModelTests.marginGapLive`.
### AC-132 (auto) — Editor labels equal Overlay labels
Statement: After every editor command the editor's label model equals the Overlay label model for the same draft.
Covers: US-110
Verify: `swift test --filter EditorModelTests.labelsMatchOverlay`.
### AC-133 (auto) — Display switch
Statement: Switching the edited Display with a dirty draft emits a prompt effect; with a clean draft it switches and re-resolves.
Covers: US-111
Verify: `swift test --filter EditorModelTests.switchDisplayPromptsWhenDirty`.
### AC-134 (auto) — Assign
Statement: The Assign command, reachable from the editor's Assign button and its key equivalent Command-Shift-A (a window key equivalent, not a global shortcut), writes exactly one Assignment for the edited Display's key referencing the draft's Layout identifier.
Covers: US-112
Verify: `swift test --filter EditorModelTests.assignWritesOnce`.
### AC-135 (auto) — Validator limits
Statement: A ratio that would leave any leaf under 1/12 on an axis returns tooSmall and leaves the draft unchanged; a Zone resolving under 120x80 pt on the current Display sets its warning flag.
Covers: US-113
Verify: `swift test --filter EditorCommandTests.minimumFractionAndWarning`.
### AC-136 (auto) — Save and Cancel
Statement: Save validates, writes the layouts document once atomically, then replaces the live Layout; Cancel writes nothing; after Save returns the file decodes to the saved document.
Covers: US-114, US-125
Verify: `swift test --filter EditorModelTests.saveWritesOnceCancelWritesNothing`.
### AC-137 (auto) — Zone count edges
Statement: A tenth Zone is badged noChord and accepted; merging the root leaf is refused.
Covers: US-115
Verify: `swift test --filter EditorCommandTests.noChordBadgeAndRootMerge`.
### AC-138 (auto) — Template picker
Statement: The Template command replaces the draft with the chosen Template at the chosen count and keeps the draft's name.
Covers: US-116
Verify: `swift test --filter EditorCommandTests.templatePicker`.
### AC-139 (manual) — Keyboard-only editor loop
Statement: From a fresh Layout with its single Zone selected, the keystrokes H, H, Command-S, Command-Shift-A, Command-W produce a three-column Layout (three Zones side by side, per AC-127) saved and assigned to the current Display without touching the mouse.
Covers: US-105, US-114, US-112
Verify: Perform the keystrokes; Shift-drag a window to confirm the Overlay shows three side-by-side Zones on that Display, and the Layouts pane shows the new Layout assigned to it.

### Appearance and Exclusions
### AC-140 (auto) — Appearance preferences
Statement: Fill color and opacity round-trip through preferences, and the Appearance sample model lists the Layouts that follow the default Margin and Gap.
Covers: US-117
Verify: `swift test --filter PreferencesTests.appearanceRoundTrip` and `AppearancePaneModelTests.listsFollowers`.
### AC-141 (manual) — Appearance applies live
Statement: Changing opacity from 0.3 to 0.8 and the Activation Modifier to Command is visible on the very next Drag Session with no relaunch.
Covers: US-088, US-117
Verify: Change both; Command-drag; observe.
### AC-142 (auto) — Exclusions model
Statement: Exclusions are a set of bundle identifiers; the pane model shows the identifier beside each name; adding from the running-apps list or a file URL stores the bundle identifier.
Covers: US-118
Verify: `swift test --filter ExclusionsPaneModelTests.bundleIdentifierKeyed`.
### AC-143 (auto) — Exclusion policy table
Statement: Phase 1 skips ownProcess, systemAgent (Dock, WindowManager, Notification Center, Control Center, loginwindow, UserNotificationCenter), excludedBundle and unresponsive from CG facts only; phase 2 skips nonStandardSubrole, sheetOrPopover, systemDialog (subroles systemDialog, systemFloatingWindow), fullScreen and positionNotSettable; sizeNotSettable returns allow with positionOnly; one row per reason per phase.
Covers: US-119, US-130
Verify: `swift test --filter ExclusionPolicyTests.table`.
### AC-144 (manual) — Automatic skips on screen
Statement: A Save sheet, a popover and Zones' own Settings window show no Overlay when Shift-dragged; Calculator Snaps by position only at the Zone's top-left.
Covers: US-119
Verify: Shift-drag each; observe.

### Import, export, persistence
### AC-145 (auto) — Export shape
Statement: Exporting all Layouts and Assignments, or one Layout, produces a document with a top-level version that decodes with the same decoder as the disk documents and re-imports to equal content.
Covers: US-120
Verify: `swift test --filter DocumentTests.exportRoundTrip`.
### AC-146 (auto) — Merge and Replace
Statement: Merge keeps existing Layouts, renames incoming name collisions with a numeric suffix and gives colliding identifiers fresh ones; Replace writes a timestamped backup of both documents, returns its name, then swaps both in one transaction.
Covers: US-121
Verify: `swift test --filter DocumentTests.mergeAndReplace`.
### AC-147 (auto) — Newer versions
Statement: Importing a document with version greater than supported is refused with a message naming both versions; a disk document with a newer version is left byte-identical and reported.
Covers: US-122
Verify: `swift test --filter DocumentTests.newerVersionRefusedAndUntouched`.
### AC-148 (auto) — Dormant Assignments
Statement: An imported Assignment for an absent key is kept in the one map, reported dormant, and used on the first snapshot containing that key.
Covers: US-123
Verify: `swift test --filter AssignmentLookupTests.dormantAppliesOnArrival`.
### AC-149 (auto) — Corrupt file
Statement: An undecodable document is renamed aside with a timestamp suffix, defaults load, and one notice event is emitted.
Covers: US-124
Verify: `swift test --filter DocumentTests.corruptFileQuarantined`.
### AC-150 (auto) — Atomic writes
Statement: With a fake filesystem that fails mid-write, the original document remains intact and decodable.
Covers: US-125
Verify: `swift test --filter DocumentTests.atomicWriteSurvivesFailure`.
### AC-151 (auto) — Import validation
Statement: A document with one Layout whose ratio is 1.0, or whose leaves overlap, or whose leaf is under 1/12, is refused naming that Layout, and neither disk document changes.
Covers: US-126
Verify: `swift test --filter DocumentTests.importValidatesWholeFile`.
### AC-152 (auto) — Migrations and golden fixtures
Statement: Each golden fixture from version 1 to current migrates to a valid document after a timestamped backup is written, and the fixture-hash test fails if a golden changes without a version bump.
Covers: US-127, US-140
Verify: `swift test --filter MigrationTests` and `FixtureHashTests`.
### AC-153 (auto) — Preferences coercion
Statement: Preferences carry schemaVersion; a blob with one unknown modifier value or one chord lacking Command or Control decodes with only that field at its default, all other fields intact, and the one-time notice flag set.
Covers: US-128
Verify: `swift test --filter PreferencesTests.fieldByFieldCoercion`.

### Reliability and diagnostics
### AC-154 (auto) — Diagnostics report
Statement: The report contains version, build, signing identity, macOS version, permission state, tap state, each Display with key and frames, Assignments, preferences, the last 200 events and skip counts grouped by bundle identifier; the event type has no title field; the report is delivered to a preview effect before any copy effect.
Covers: US-129, US-146
Verify: `swift test --filter DiagnosticsTests.reportContentsAndPreviewFirst`.
### AC-155 (auto) — Skip reasons logged
Statement: Every skip produces one log event with its reason and increments that reason's count in the ring.
Covers: US-130
Verify: `swift test --filter DiagnosticsTests.skipReasonsCounted`.
### AC-156 (auto) — Idle schedule
Statement: With the fake Clock and no Drag Session, tap recovery or Display reconfiguration in flight, exactly these timers exist per permission state: notGranted and revoked a 1 s trust poll; granted a 5 s health tick and no trust poll; needsRelaunch a 1 s trust poll; suspect its 3 s resolve timer (AC-007) and no trust poll; nothing else. The only other timers are transient and exist solely while their trigger is pending, each cancelled when it resolves: the 30 s dead-tap retry after tapLost (AC-011), the 1 s nil-UUID retry at most three times (AC-123) and the 200 ms topology debounce (AC-124). Frame sampling is requested only in pressed and never after moving.
Covers: US-131
Verify: `swift test --filter IdleScheduleTests.exactTimersPerState`, `IdleScheduleTests.transientTimersCancelWhenResolved` and `DragSessionReducerTests.noSamplesAfterMoving`.
### AC-157 (manual) — Idle CPU
Statement: With twenty snapped windows and no interaction for ten minutes, Zones averages under 1 percent CPU in Activity Monitor.
Covers: US-131
Verify: Snap twenty windows; wait ten minutes; read the average.
### AC-158 (auto) — Heartbeat isolation
Statement: Heartbeat results feed only the permission machine, never AppHealth; at most one heartbeat is in flight; none is issued while the reducer is not idle.
Covers: US-004, US-131
Verify: `swift test --filter PermissionMachineTests.heartbeatIsolation`.
### AC-159 (auto) — Typed results and timeouts
Statement: FrameWriteResult has exactly the cases applied, clamped, refused, timedOut, elementGone, noOp; the WindowActor sets a 250 ms per-app and a 1 s process-wide messaging timeout at launch.
Covers: US-132, US-139
Verify: `swift test --filter WindowActorTests.timeoutsSetAtLaunch` and a compile-time exhaustive switch in `FrameWriteResultTests`.

### Maintainer gates
### AC-160 (auto) — One command, CI
Statement: `swift test` from the repository root exits 0; the single CI workflow `.github/workflows/ci.yml` has a step running `swift test` and a step running `xcodebuild` with the `build` action, and triggers on `pull_request` to `main` and on `workflow_dispatch` with no `push` trigger (ADR-0026, challenge C11); and `scripts/merge-ticket.sh` runs `swift build`, `swift test` and `xcodebuild` before every merge into `integration`, so every ticket merge and every release pull request runs both checks.
Covers: US-137
Verify: `swift test` exits 0; `swift test --filter 'GateScriptTests/ciTriggersArePullRequestToMainAndManual'` passes; `grep -c 'swift test' .github/workflows/ci.yml` prints a number of at least 1; `grep -cE 'xcodebuild .*\bbuild\b' .github/workflows/ci.yml` prints a number of at least 1; `grep -c 'workflow_dispatch:' .github/workflows/ci.yml` prints a number of at least 1; `grep -c '^  push:' .github/workflows/ci.yml` prints `0`; `ls .github/workflows | wc -l` prints `1`.
### AC-161 (auto) — Strict concurrency
Statement: `Package.swift` sets `swiftLanguageModes: [.v6]` (Swift 6 language mode, which enforces complete strict concurrency) for the whole package, `project.yml` sets `SWIFT_STRICT_CONCURRENCY: complete` and `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` for the app target, the package including its test targets builds with warnings as errors, the app target builds with both flags forced on the command line, and the package and app sources together contain exactly one `@unchecked Sendable`, on the window handle box type in the `ZonesWindowing` target.
Covers: US-138
Verify: `grep -cE 'swiftLanguageModes:\s*\[\s*\.v6\s*\]' Package.swift` prints `1`; `grep -c 'SWIFT_STRICT_CONCURRENCY: complete' project.yml` prints `1` and `grep -c 'SWIFT_TREAT_WARNINGS_AS_ERRORS: YES' project.yml` prints `1`; `swift build --build-tests -Xswiftc -warnings-as-errors` exits 0; `xcodegen generate && xcodebuild -quiet -project Zones.xcodeproj -scheme Zones -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES SWIFT_STRICT_CONCURRENCY=complete build` exits 0; `grep -rn '@unchecked Sendable' Sources App | wc -l` prints `1` and that line's path lies under `Sources/ZonesWindowing/`.
### AC-162 (auto) — App-target hygiene gate
Statement: `scripts/hygiene-gate.sh` scans the app target's Swift sources and exits 0 only when they contain zero occurrences of `try!`, `as!` or `fatalError(` on a line without the `zones:allow` marker, zero `import ApplicationServices` lines and zero uses of symbols beginning with `CGWindowList`; those imports and symbols appear only in the production adapter sources; the CI workflow runs the script as a step after `swift test`.
Covers: US-144
Verify: `scripts/hygiene-gate.sh` from the repository root exits 0 and prints exactly three lines: `unsafe-ops: 0`, `ax-imports: 0`, `cgwindowlist-uses: 0`; adding `try!` to any app-target source makes it exit 1 with `unsafe-ops: 1`; the CI workflow definition contains a step invoking `scripts/hygiene-gate.sh`.
### AC-163 (auto) — Fakes for every seam
Statement: Each protocol seam (WindowSystem, WindowEnumerator, InputSource, DisplayProvider, OverlayPresenter, HotkeyRegistrar, LoginItemService, PermissionProbe, Clock) has a scriptable fake with a response queue, a call log and fake-Clock latency.
Covers: US-135
Verify: `swift test --filter FakeContractTests` (one case per seam exercising queue, log and latency).
### AC-164 (auto) — One coordinate conversion
Statement: AppKit to AX to AppKit round-trips to identity for random rectangles on the 3-Display fixture (primary centered, 2x Display left, 1x portrait Display above with negative origin), and display(for:) picks the maximum-intersection Display.
Covers: US-136
Verify: `swift test --filter CoordinateSpaceTests.roundTripAndDisplayFor`.
### AC-165 (auto) — Seed in failure message
Statement: The generator's failure reporter, invoked in a passing test for a seeded case that the test marks as failing, returns a message containing the seed as an integer and the generated Layout's description; the suite itself passes.
Covers: US-141
Verify: `swift test --filter GeneratorTests.failureMessageNamesSeed`.
### AC-166 (auto) — Reducer invariants
Statement: For random event streams: an Overlay is shown only on entry to armed; every path to idle hides a shown Overlay; snap is emitted only with the Activation Modifier down at mouseUp; restore is never emitted from moving; a Span release then re-press preserves the set; no AX-bound effect is emitted from pressed before the first returned sample.
Covers: US-134
Verify: `swift test --filter ReducerInvariantTests`.
### AC-167 (auto) — Ticket shape
Statement: Every ticket object in `docs/tickets/graph.json` carries non-empty string fields `protocol` (the protocol seam it implements, or the literal `none`), `fake` (the fake it ships, or `none`) and `tests` (the Swift Testing suites or cases it adds, never `none`); `scripts/ticket-lint.sh` exits 1 naming the first ticket id that lacks any of the three.
Covers: US-142
Verify: `scripts/ticket-lint.sh` from the repository root exits 0 and prints `tickets: <N>, missing-fields: 0`; removing `fake` from one ticket in a scratch copy and running `scripts/ticket-lint.sh <copy>` exits 1 and names that ticket id.
### AC-168 (manual) — Release checklist
Statement: `docs/release-checklist.md` is a one-page table with a header recording the release tag, the macOS version and the tester, and one row per check below; each row names the AC whose expected result is its pass condition and has a result cell holding `pass` or `fail`. The rows, with their pass conditions by reference: grant from a clean account (one onboarding window, dismissed within 1.5 s of the toggle: AC-004, AC-005); Shift-drag on every Display dropping on a Zone (lands on the Overlay rectangle, no other window moves: AC-070); dropping on a Gap (Snaps into the nearest Zone, never Restores: AC-080); dropping on the menu bar with an Original Frame (fills dim, window returns to its pre-grab frame: AC-091, AC-096) and without one (nothing dims, window stays where macOS left it: AC-091); pause on the title bar then drag (Overlay appears, Snap works: AC-055); Control-sweep a diagonal Span, release Control, skim a seam, drop (union of the swept Zones on the Span's Display: AC-081, AC-083, AC-085); send to each Zone by chord including N beyond the count (lands in Zone N; the absent N does nothing: AC-098, AC-101); chord mid-drag (ignored, one log line: AC-110); cycle after a Span and after a clamp (next Zone per the cycle table: AC-100); Restore, hand-move, Snap, Restore (returns to the hand-placed frame: AC-093); revoke mid-drag and while idle (badge and onboarding window return, no crash: AC-007, AC-009); unplug a Display mid-session (Overlay re-arms from the new geometry, no window moves: AC-060, AC-119); mirror, pick a Layout, unmirror (mirror set keyed by the master, each Display resumes its own Assignment: AC-122); import with Merge and with Replace (merged names suffixed, Replace writes a named backup first: AC-146); Stage Manager on (Shift-drag on the current stage Snaps and no window on another stage moves: AC-070, AC-041).
Covers: US-143
Verify: Before the release is tagged, every row of `docs/release-checklist.md` is marked `pass` and the header carries the release tag and the macOS version it was run on; a row marked `fail` or left blank blocks the release; `grep -cE 'AC-[0-9]{3}' docs/release-checklist.md` prints a number equal to the row count, and `grep -cE '\|\s*fail\s*\|' docs/release-checklist.md` prints `0` for the committed copy on the release tag.
### AC-169 (auto) — Logger facade
Statement: The logger exposes one category per module, a production sink of the unified log and a test sink that is an array, and the ring never exceeds 200 events.
Covers: US-146
Verify: `swift test --filter DiagnosticsTests.ringBoundedAndSinks`.

## 6. Out of scope

- Auto-update, cloud sync, iCloud, telemetry or any network access, localization beyond English, App Store distribution (BRIEF).
- Windows-parity edge cases from FancyZones (BRIEF).
- Re-snapping or re-laying out windows after a Display, Space or resolution change; moving windows when a Display disappears (BRIEF, ADR-0014).
- Tiling: evicting, rearranging or moving any window other than the one being snapped or restored (BRIEF, ADR-0007).
- Per-Space Assignments unless SPK-001 passes; Space creation or navigation.
- Screen Recording, Input Monitoring or any permission other than Accessibility; reading or storing window titles.
- Any private API; any third-party dependency in v1; a helper process or XPC service.
- Overlapping or non-rectangular Zones; canvas-style free rectangles; a third leaf kind.
- Non-sibling merge (same-axis chain merge and general re-treeing are spikes, see SPK-015).
- Escape key to cancel an armed Drag Session (requires key tapping).
- Text or hints on the Overlay beyond Zone Numbers; a first-use hint.
- Window-level animation of Snaps; snapping during a resize gesture; snapping on window creation; snapping by click or window menu.
- Remembering a window's Zone across relaunch; the in-session last-Snap record is memory only.
- Special handling of Stage Manager beyond working on the current stage (manual checklist row only).
- A built-in list of specific system chords; recorder warnings are rules over modifier sets.
- Guessing that a new Display identifier is an old Display; recovery is the user-driven Copy Assignment.
- Shortcuts for "move to next Display", "swap windows between Zones" or per-app default Zones.
- Observing moved or resized notifications; a hardware key kind persisted alongside the UUID.

## 7. Spikes

Each spike returns a verdict note before the dependent tickets start. "Depends" lists the ACs whose expected result the verdict fixes.

- SPK-001 Per-Space identification via hidden witness windows (ADR-0013). Method: one invisible managed window per (Display, Space); on each active-Space change the witness with isOnActiveSpace true identifies the Space. Pass: identifies the Space correctly in 20 of 20 switches across Space creation, deletion, Display reconnect and a full-screen Space, with no private API. Fail: per-Space Assignments move to out of scope. Depends: none in v1; a pass adds an optional Space token to the Assignment record (document version 2).
- SPK-002 Click-through panel during a drag. Pass: a screenSaver-level, click-through, non-key panel ordered front during a title-bar drag leaves the drag, the frontmost app and the key window unchanged; visibility recorded over a full-screen Space, a Split View Space and a Space created after launch; whether a managed window can be dropped on a Display whose active Space is full-screen; what visibleFrame reports with the menu bar auto-hidden. Depends: AC-044, AC-046, AC-045, AC-062.
- SPK-003 Listen-only tap needs only Accessibility. Pass: a listen-only session tap for left mouse down, dragged, up and flagsChanged is created and delivers events on clean macOS 14, 15 and the current release with only Accessibility granted; latency under one frame at 120 Hz. Fail: ADR-0020 must be revisited. Depends: AC-003, AC-065, AC-066.
- SPK-004 NSWindow.windowNumber equals the CGWindowID, and the CGEvent window-under-pointer field equals the CGWindowList id, on macOS 14 and 15; optionIncludingWindow alone returns the window. Pass: equality in 50 of 50 windows per OS. Depends: AC-044, AC-056, AC-067.
- SPK-005 Stable dev identity. Pass: the self-signed "Zones Dev" build keeps the Accessibility grant across three rebuilds and its designated requirement has no cdhash. Depends: AC-013.
- SPK-006 Revocation signals. Pass criteria recorded, not required: whether a trivial AX read of the system-wide element returns apiDisabled within 5 s of revoking a running process (enables the heartbeat), what the trust probe reads afterwards, and whether an existing tap keeps delivering events. Depends: AC-007, AC-009, AC-156, AC-158.
- SPK-007 AX moved and resized notification cadence during a live drag in Finder, Safari and Chrome. Pass: documented cadence; confirms they stay bookkeeping-only (ADR-0006). Depends: AC-093.
- SPK-008 Stacked identical windows. Pass: for four same-size windows of one pid, the first frame sample after the first dragged event changes exactly one candidate's origin in 20 of 20 trials. Depends: AC-056, AC-057.
- SPK-009 Overlay frame time. Pass: persistent CALayers updated per dragged event stay under one frame at 120 Hz; SwiftUI hosting measured and adopted only if it also passes. Depends: AC-040, AC-039.
- SPK-010 Write protocol app matrix: Finder, Safari, Terminal, System Settings, Calculator, Chrome, VS Code, Slack, IntelliJ, a SIGSTOP'd app. Pass: read-back deltas, wall time per Snap, timeout behavior and Enhanced UI side effects recorded; VoiceOver survives the toggle. Depends: AC-071, AC-075, AC-078.
- SPK-011 Login item behavior on a clean account: status after disabling in System Settings (requiresApproval or notFound), register from a DMG-mounted quarantined copy, after moving the app. Depends: AC-027, AC-028.
- SPK-012 Identical Displays. Pass: two Displays of one model report distinct UUIDs on the current release; the fallback with zero serials is recorded. Depends: AC-119, AC-123.
- SPK-013 AXObserver thread. Pass: callbacks for a run-loop source added on a dedicated thread arrive on that thread and keep arriving after the thread idles for 60 s. Depends: AC-093.
- SPK-014 Key status from a Carbon hotkey on macOS 14 and 15 with another app frontmost. Recorded, not required: for each OS, whether the Settings window opened by the hotkey handler becomes key (typing reaches it) or only orders front, with and without a prior `activate`. The resulting per-OS table fixes the expected key status in AC-023; ordering front is required regardless. Depends: AC-023.
- SPK-015 Same-axis chain merge (challenge C3). Pass: a deterministic re-chaining formula (merging A and B in A | (B | C) yields ratio r1 + (1 - r1) * r2 with C reparented) with a golden table over every Template-derived tree, undo exact. A pass opens a new ADR amending ADR-0003; until then AC-129 holds. Depends: AC-129.
- SPK-016 CG window description polling as the move-confirmation source (ADR-0006 alternative). Pass: polling CGWindowListCreateDescriptionFromArray for the candidate ids confirms a move within two samples at 60 Hz and costs the target app nothing while SIGSTOP'd. A pass opens a new ADR; until then AX frame polling stands. Depends: AC-055, AC-056, AC-078.
- SPK-017 CGWindowList with Screen Recording denied. Pass: bounds, layer and pid are present with nil names, and the pid plus frame match still resolves the dragged window. Depends: AC-003, AC-056.
- SPK-018 Sleep and wake on a lid-closed docked Mac. Pass: the tap and panels survive or are recreated by the wake path, and each Display's UUID persists. Depends: AC-024, AC-025.

## 8. Resolved disagreements

- Focus Template shape: options 20/60/20 three Zones (center is Zone 2), inert leaves, or a Layout-level surround fraction with one Zone; chose the surround (Focus is one Zone numbered 1) because ADR-0005 names one center Zone and a third leaf kind contradicts ADR-0003; recorded as challenge C1.
- Span Modifier release: options clear on re-press, FancyZones hysteresis (keep inside the union, replace outside), or freeze; chose freeze, re-press resumes, Activation release clears, because the drop target must never change with no key pressed (LI-009).
- Span across Displays: options clear or suspend; chose suspend and resume with a dimmer drawing, because a seam skim must not lose a sweep.
- Restore trigger: options Gap and Margin Restore, or only outside the visible frame; chose outside the visible frame with Gap and Margin snapping to the nearest Zone, because an 8-point miss must not teleport a window; recorded as challenge C2.
- Original Frame lifetime: options keep until the window closes, or also clear on Restore; chose clear on a successful Restore so Snap, Restore, hand-move, Snap, Restore returns the hand-placed frame; recorded as challenge C2.
- Mouse-path Original Frame: options the pre-write frame or the mouse-down frame; chose the mouse-down frame of the resolved window, because "before its first Snap" means before the grab.
- Relaunch button: options always offered in revoked, or a separate needsRelaunch state after 3 failed recreations over 10 s with the probe true; chose the separate state, because a probe reading false means the grant is certainly absent and a button that relaunches into an untrusted app teaches that it is dead; a sentence explains the delay.
- Idle revocation signal: options none while granted, or a 5 s heartbeat; chose a spike-gated heartbeat folded into the single 5 s health tick, off unless SPK-006 proves the signal.
- Trust poll period: options 0.5 s while onboarding is visible, or 1 s; chose 1 s because ADR-0021 fixes it; AC-005 allows 1.5 s.
- Move confirmation source: options AX frame polling or CG window description polling; chose AX frame polling because ADR-0006 names it; sampling starts at the first dragged event (a click costs no AX call), and the CG alternative is SPK-016.
- Candidate cap: options two or four held candidates; chose four by z-order with one batched read per tick, because a power user's identical terminals come in threes and fours.
- Frame sampling after move confirmation: options poll through armed or stop; chose stop at moving, with one frame read at mouse-up, so a timeout can never abort a live gesture and the actor idles during the armed phase.
- Timeout handling: options cooldown on first timeout, or retry once then cooldown; chose one immediate retry then abort and cooldown, per the research recommendation; worst case 0.5 s.
- Cooldown length: options 5 s or 10 s; chose 10 s as a named constant.
- Cycle base: options last-Snap record with 1 pt match, or maximum intersection only; chose the record with a 2 pt match (Chromium settles a point) and maximum intersection with a Span tie rule as the fallback, because intersection alone gives Layout-dependent results after a Span.
- Recorder warnings: options a six-chord data fixture, rule-based warnings, or none; chose rules (Command-only, Command+Shift-only, Control-only with arrow or digit), because a chord list rots per release and the rules cover the same collisions.
- Mirror sets: options persist under the master key, or session-only while mirroring; chose persist under the master, because the master's UUID is stable and the rule protected nothing.
- DisplayKey kinds: options uuid, hardware and unstable, or uuid and unstable only; chose two kinds with a PersistentDisplayKey holding only the UUID, because a hardware key's uniqueness depends on which Displays happen to be attached (ADR-0012).
- Merge scope: options siblings only, or siblings plus same-axis chain; chose siblings only per ADR-0003, with chain merge as SPK-015.
- Margin and Gap on disk: options nil means default, or explicit numbers; chose explicit numbers on every persisted Layout, so a document never depends on a preference outside it; built-ins are generated from the defaults at load.
- Rounding: options remainder to the last Zone, round shared Zone edges, or round dividers and the Gap once; chose dividers and Gap, because every Gap must be the same pixel count and the result must not depend on traversal order.
- Editor window: options a full-Display window or a resizable window defaulting to the visible frame over a translucent backdrop; chose the latter, because a Display-sized window is managed by Stage Manager and hides the windows being laid out.
- Hotkey during a Drag Session: options a reducer event or a dispatcher check; chose the dispatcher reading the reducer's idle flag, so the reducer's event set stays what the gesture needs.
- Enhanced UI policy values: options toggle, leave, auto or toggle and leave; chose toggle and leave (default toggle, ADR-0022), because skipping the pair when the attribute is absent or off already is the measurable "auto".
- Enhanced UI recovery record: options none, per-Snap, or once per app per session with the prior value after the frame write; chose the last, because VoiceOver users need the crash case closed and the hot path must stay clean.
- Exclude menu item: options confirmation alert or a checkable item; chose checkable (the same click undoes it).
- Delete an assigned Layout: options fall back to Priority Grid with confirmation, or require a replacement pick; chose require a replacement, so no Assignment ever dangles.
- Activation policy for Settings: stays accessory; the app activates and the window becomes key where macOS allows; nothing toggles on close (ADR-0019).

### Challenges to ADRs (recorded, not silently applied; each needs a new ADR or an amendment)
- C1 ADR-0003 and CONTEXT ("tiles one display") versus ADR-0005 ("one center zone at 60 percent"): a split tree whose every leaf is a Zone cannot express Focus. Evidence: all three drafts and every critique round. Amendment: "tiles the Layout rectangle", with a Layout-level normalized surround fraction (default 0, Focus 0.2, maximum 0.45) applied before Margin. Recorded 2026-10-24 as the amendment paragraphs of ADR-0003 and ADR-0005; adopted in LI-004, AC-088 and AC-116; the Templates ticket may proceed.
- C2 ADR-0009: "ends outside every zone" is refined to "ends outside the Display's visible frame" (Gap, Margin and surround snap to the nearest Zone), and a successful Restore forgets the Original Frame in addition to window close and app quit. Evidence: Gap drops teleporting windows (all critiques); the Snap-Restore-hand-move sequence. Recorded 2026-10-24 as the amendment paragraph of ADR-0009; adopted in AC-080, AC-089, AC-090, AC-091, AC-093.
- C3 ADR-0003 merge wording: same-axis chain merge is wanted (Columns 3, Zones 1 and 2) but re-chains a subtree. Not adopted; SPK-015 delivers the formula and golden table first.
- C4 ADR-0018: "size or position is not settable" now reads "position is not settable"; a size-locked window gets a position-only Snap at the Zone's top-left. Evidence: ax-window-moves implications 2 and 3; Calculator and inspector windows. Recorded 2026-10-24 as the amendment paragraph of ADR-0018; adopted in AC-143 and AC-144.
- C5 ADR-0021: polling AXIsProcessTrusted cannot detect revocation of a running process (event-taps-tcc Gotchas, DTS). The poll stays for the first grant and in revoked and needsRelaunch, and stops in granted; revocation is derived from runtime signals through a suspect state; a needsRelaunch state offers "Quit and Reopen". Recorded 2026-10-24 as the amendment paragraph of ADR-0021; adopted in AC-006, AC-007, AC-008, AC-156.
- C6 ADR-0022: no behavior change; refinements adopted are restore in a defer on every path, skip the pair when absent or off, drain on Quit and revocation, a once-per-app recovery record with the prior value, and an EnhancedUIPolicy of toggle or leave.
- C7 ADR-0015: the 250 ms timeout alone lets one hung app cost 2 s on the serial actor over an eight-call sequence; the abort-at-second-timeout rule (one retry) is added so the worst case is 0.5 s. Adopted in AC-077.
- C8 ADR-0006: names AX frame polling; the platform persona proposes CG window description polling so a plain drag costs the target app nothing. Not adopted; SPK-016 measures it for a possible new ADR.
- C9 ADR-0012: the UUID can read nil mid-reconfiguration and may collide for identical panels with zero serials; refinement adopted is a Clock-driven retry and an unstable, never-persisted fallback key with a session-only Assignment. The UUID remains the only persisted key.
- C10 ADR-0008: silent on Span Modifier release; the freeze rule above is the decision.
- C11 ADR-0024 / AC-160 (2026-10-24, user decision): CI on every push exhausted the free GitHub Actions allowance for macOS runners on a private repository. CI now runs on pull requests to `main` and on manual dispatch; `scripts/merge-ticket.sh` is the per-ticket gate; the repository goes public at release. Recorded as ADR-0026; AC-160 amended.

## 9. Traceability

| US | AC ids |
|---|---|
| US-001 | AC-001, AC-002 |
| US-002 | AC-004 |
| US-003 | AC-005, AC-006 |
| US-004 | AC-007, AC-009, AC-158 |
| US-005 | AC-008, AC-010 |
| US-006 | AC-003 |
| US-007 | AC-011 |
| US-008 | AC-012, AC-028 |
| US-009 | AC-013 |
| US-010 | AC-014, AC-015 |
| US-011 | AC-018, AC-019 |
| US-012 | AC-020 |
| US-013 | AC-021 |
| US-014 | AC-016 |
| US-015 | AC-017, AC-078 |
| US-016 | AC-022, AC-023 |
| US-017 | AC-024, AC-025 |
| US-018 | AC-026 |
| US-019 | AC-027, AC-028 |
| US-020 | AC-015, AC-029, AC-030 |
| US-021 | AC-031 |
| US-022 | AC-032, AC-033 |
| US-023 | AC-034 |
| US-024 | AC-035, AC-036 |
| US-025 | AC-031, AC-037 |
| US-026 | AC-032, AC-038 |
| US-027 | AC-033, AC-039, AC-040 |
| US-028 | AC-041, AC-070 |
| US-029 | AC-042 |
| US-030 | AC-043, AC-044 |
| US-031 | AC-045, AC-046 |
| US-032 | AC-047 |
| US-033 | AC-048 |
| US-034 | AC-049 |
| US-035 | AC-050 |
| US-036 | AC-051 |
| US-037 | AC-052 |
| US-038 | AC-053 |
| US-039 | AC-054 |
| US-040 | AC-055 |
| US-041 | AC-056, AC-057 |
| US-042 | AC-058, AC-064 |
| US-043 | AC-059 |
| US-044 | AC-060, AC-061 |
| US-045 | AC-046, AC-062 |
| US-046 | AC-063, AC-064 |
| US-047 | AC-065, AC-066 |
| US-048 | AC-047, AC-067 |
| US-049 | AC-068 |
| US-050 | AC-068, AC-069, AC-070 |
| US-051 | AC-071 |
| US-052 | AC-072 |
| US-053 | AC-070, AC-073 |
| US-054 | AC-074, AC-075 |
| US-055 | AC-074, AC-075, AC-076 |
| US-056 | AC-077, AC-078 |
| US-057 | AC-079 |
| US-058 | AC-080 |
| US-059 | AC-081 |
| US-060 | AC-081 |
| US-061 | AC-082 |
| US-062 | AC-083 |
| US-063 | AC-084, AC-085 |
| US-064 | AC-086 |
| US-065 | AC-087 |
| US-066 | AC-088 |
| US-067 | AC-039, AC-053 |
| US-068 | AC-089, AC-096 |
| US-069 | AC-090, AC-097 |
| US-070 | AC-082, AC-091 |
| US-071 | AC-091, AC-092 |
| US-072 | AC-090, AC-093 |
| US-073 | AC-094 |
| US-074 | AC-095 |
| US-075 | AC-089 |
| US-076 | AC-097, AC-098 |
| US-077 | AC-099 |
| US-078 | AC-100 |
| US-079 | AC-101 |
| US-080 | AC-102 |
| US-081 | AC-103 |
| US-082 | AC-104 |
| US-083 | AC-105, AC-106 |
| US-084 | AC-097, AC-107 |
| US-085 | AC-092, AC-108 |
| US-086 | AC-109 |
| US-087 | AC-110 |
| US-088 | AC-111, AC-141 |
| US-089 | AC-112 |
| US-090 | AC-113 |
| US-091 | AC-114, AC-115 |
| US-092 | AC-116 |
| US-093 | AC-117 |
| US-094 | AC-118, AC-119 |
| US-095 | AC-118, AC-119 |
| US-096 | AC-120 |
| US-097 | AC-121 |
| US-098 | AC-122 |
| US-099 | AC-119, AC-120, AC-123 |
| US-100 | AC-123 |
| US-101 | AC-060, AC-124 |
| US-102 | AC-125 |
| US-103 | AC-114 |
| US-104 | AC-022, AC-126 |
| US-105 | AC-127, AC-139 |
| US-106 | AC-128 |
| US-107 | AC-129 |
| US-108 | AC-130 |
| US-109 | AC-131 |
| US-110 | AC-132 |
| US-111 | AC-133 |
| US-112 | AC-134, AC-139 |
| US-113 | AC-135 |
| US-114 | AC-136, AC-139 |
| US-115 | AC-137 |
| US-116 | AC-138 |
| US-117 | AC-140, AC-141 |
| US-118 | AC-067, AC-142 |
| US-119 | AC-143, AC-144 |
| US-120 | AC-145 |
| US-121 | AC-146 |
| US-122 | AC-147 |
| US-123 | AC-148 |
| US-124 | AC-149 |
| US-125 | AC-136, AC-150 |
| US-126 | AC-151 |
| US-127 | AC-152 |
| US-128 | AC-153 |
| US-129 | AC-015, AC-154 |
| US-130 | AC-143, AC-155 |
| US-131 | AC-006, AC-156, AC-157, AC-158 |
| US-132 | AC-078, AC-159 |
| US-133 | AC-093 |
| US-134 | AC-166 |
| US-135 | AC-163 |
| US-136 | AC-164 |
| US-137 | AC-160 |
| US-138 | AC-161 |
| US-139 | AC-159 |
| US-140 | AC-152 |
| US-141 | AC-165 |
| US-142 | AC-167 |
| US-143 | AC-168 |
| US-144 | AC-162 |
| US-145 | AC-039 |
| US-146 | AC-154, AC-169 |
