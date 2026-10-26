# Zones spec draft — maintainer persona (long-term maintainability), revised after round 3

## Problem Statement

A person with one or more Displays wants windows to land in predictable places without hand-positioning them. macOS offers no FancyZones-style zoning: Mission Control tiles two windows at most, third-party tools either use private APIs (break on OS updates) or demand several permissions. The person wants a small menu-bar tool that asks for one permission, shows where a window will land while they drag, snaps on drop, and stays out of the way. They also want the tool to keep working across OS updates, Display reconnects, and app quirks, and when it misbehaves they want to paste one diagnostics blob into a bug report instead of describing the problem from memory.

## Solution

Zones is a menu-bar-only app. The person grants Accessibility once; Zones tells them clearly when that grant is missing or lost. Each Display has an Assignment to a Layout, chosen from a Template or built in a Layout editor by splitting, merging, and resizing Zones and setting Margin and Gap. During a Drag Session with the Activation Modifier held, an Overlay shows the Layout and highlights the Zone under the cursor; releasing the mouse Snaps the window there. Holding the Span Modifier lets the person Span several Zones. Keyboard shortcuts send the focused window to a Zone Number, cycle Zones, Restore the Original Frame, and open the editor and Settings. Exclusions keep chosen apps untouched. Layouts and Assignments are versioned JSON that can be exported and imported. Every rule that decides what Zones does is a pure function tested headless; the AX, CG, and AppKit edges sit behind protocols; nothing on the menu-bar path can block or crash.

## User Stories

### Shell, onboarding, permission
- US-001: As a user, I want Zones to live only in the menu bar, so that it never takes a place in the Dock or steals focus.
- US-002: As a first-time user, I want one onboarding window explaining why Accessibility is needed with a button that opens the right System Settings pane, so that I can grant it in two clicks.
- US-003: As a user, I want Zones to notice the grant within a second of my flipping the toggle and proceed without a relaunch, so that onboarding feels immediate.
- US-004: As a user whose grant was revoked, I want the menu-bar icon to show a badge and the onboarding window to return at the first failed call or tap signal, and within five seconds while idle if the heartbeat spike passes, so that I know why dragging stopped working and am never promised a signal macOS may not give.
- US-005: As a user who revoked and re-granted, I want a "Quit and Reopen" button only when Zones has confirmed the grant is back but the running process still cannot use it, so that the button is never offered while it would do nothing.
- US-006: As a user, I want Zones to never request Screen Recording or Input Monitoring, so that the privacy footprint stays at one permission.
- US-007: As a user launched at login, I want no onboarding or Settings window to appear on that path when the grant is present, so that login is silent.
- US-008: As a user, I want the menu to show a Layout picker for the Display under the cursor (Templates named with their Zone counts, then custom Layouts, active one checked), Edit Layouts, Settings, and Quit, so that common actions are one click away.
- US-009: As a user, I want the menu to open instantly even while a target app is hung, so that Zones never feels frozen.
- US-103: As a user without the grant, I want a "Grant Accessibility" menu item and nothing else window-like at login, so that a login-time launch never steals focus.
- US-104: As a user, I want Settings General to show permission state and event-tap health, and the menu-bar icon to badge for either, so that a dead drag is diagnosable in seconds.
- US-105: As a user, I want the first modifier-drag after wake from sleep to work, so that a lid-closed docked Mac needs no relaunch.
- US-106: As a user, I want Quit to tear down the event tap and panels and restore anything Zones changed in other apps, so that nothing lingers.
- US-124: As a first-time user, I want onboarding to end with a one-page cheat sheet (hold Shift to see Zones, add Control to Span, Control+Option+N to send) and General to show my two modifiers as key caps, so that I can use Zones before reading anything else.
- US-125: As a user, I want Settings and the editor to open on the Display under the cursor, on the current Space, and become key, and the menu-bar icon to be a template image, so that a menu-bar app behaves like a native one when I ask for a window.
- US-126: As a user, I want an "Exclude <App Name>" item in the menu for the frontmost app, shown checked when it is already excluded so the same click undoes it, so that exclusion takes one click and one click back.
- US-142: As a user, I want a "Reset and re-onboard" action in General that returns Zones to the not-granted flow without touching my Layouts or preferences, so that I can recover from a confused permission state.

### Layouts and Templates
- US-010: As a user, I want Columns and Rows Templates with 2 to 5 Zones, so that I can split a Display quickly.
- US-011: As a user, I want Grid Templates of 2x2 and 3x3, so that I can arrange many small windows.
- US-012: As a user, I want a Priority Grid Template with a wide center Zone, so that one main window gets room and two side Zones hold the rest.
- US-013: As a user, I want a Focus Template whose single Zone takes the center 60 percent of the Display and is Zone Number 1, so that one window is centered with breathing room and one chord sends it there.
- US-014: As a user, I want any Display without an Assignment to use Priority Grid, so that Zones is useful before I configure anything.
- US-015: As a user, I want to pick a Layout per Display from the menu or Settings, so that my wide Display and my laptop Display differ.
- US-016: As a user, I want an Assignment to survive unplugging and replugging the same Display, so that I do not reconfigure every time I reconnect.
- US-017: As a user, I want a new, never-seen Display to get the default Layout, so that nothing breaks when I present on a borrowed projector.
- US-018: As a user, I want Layout geometry stored as fractions of the Display, so that one Layout fits any resolution.
- US-019: As a user, I want Margin and Gap in points per Layout, with a default Margin and Gap in Appearance that Templates and new Layouts use, so that built-ins match my taste without duplicating them.
- US-020: As a user, I want Zone Numbers counted row by row from the top-left and shown on the Overlay, so that shortcut digits match what I see.
- US-021: As a user, I want Zone Numbers to update immediately after any edit, so that a stale number never sends a window somewhere unexpected.
- US-107: As a user, I want Templates to be read-only and "Duplicate" to create a custom Layout from one, so that the built-ins are always a known starting point.
- US-127: As a user, I want the Layouts pane to list disconnected Displays with name, last size and Assignment, with "Copy Assignment to <attached Display>" and "Forget", so that moving between desks never needs a guess from Zones.
- US-128: As a user with two Displays whose hardware gives no stable identifier, I want each to use the default Template until I pick a Layout for it from the menu, that pick to last for the session only, and the Layouts pane to say why it is not saved, so that identical hardware is never silently conflated and never locks me to the default.
- US-147: As a user who picks a Layout while Displays are mirrored, I want it to apply to the mirrored set for this session and each Display to keep its own saved Assignment when I unmirror, so that a presentation never rewrites my desk setup.

### Layout editor
- US-022: As a user, I want to split a Zone horizontally or vertically, so that I can refine a Template.
- US-023: As a user, I want to merge two sibling Zones back into one, and to be told why a merge is not possible with a hint at the split order that gives the shape I want, so that I can undo a split without starting over and learn the rules fast.
- US-024: As a user, I want to drag the divider between Zones to resize them, so that proportions match my windows.
- US-025: As a user, I want the editor to refuse a resize that would make a Zone smaller than a minimum fraction of the Display, and to show the resulting point size on the Display being edited with a warning under a usable size, so that slivers are impossible and tiny Zones are visible before I save.
- US-026: As a user, I want to set Margin and Gap in the editor and see them live, so that I can judge Margin and Gap before saving.
- US-027: As a user, I want to name, duplicate, and delete custom Layouts, so that I can keep variants.
- US-028: As a user, I want to be stopped from deleting a Layout that a Display is assigned to unless I pick a replacement, so that no Display ends up with a dangling Assignment.
- US-029: As a user, I want undo and redo in the editor, so that mistakes are cheap.
- US-030: As a user, I want the editor to open as a full-Display window on the Display under the cursor, drawing that Display's Layout at real scale where the Overlay will draw it, so that I edit what I am looking at and eight points of Gap look like eight points.
- US-031: As a user, I want edits to apply only when I press Save, and Cancel to leave the live Layout untouched, so that experimentation is safe.
- US-129: As a user, I want to select a Zone and split it with one key (H or V), merge it with its sibling with one key (M), and save and close with shortcuts, so that a three-column Layout takes three keystrokes and no mouse.
- US-130: As a user, I want a dragged divider to snap to halves, thirds, quarters of its parent and to collinear dividers, with a modifier for free drag, and arrow keys to nudge the selected divider by one point (ten with Shift), so that alignment is instant and exact.
- US-131: As a user, I want Zone Numbers drawn in the editor as they will appear on the Overlay, updating as I split and merge, so that I can plan chords while designing.
- US-132: As a user, I want to switch the Display being edited from inside the editor (including a disconnected Display at its last known size), prompted first when I have unsaved changes, so that I fix every Layout without reopening it.
- US-143: As a user with a Layout of more than nine Zones, I want Zones beyond nine badged "no chord" in the editor and never refused, so that a 3x3 plus one split is still allowed.
- US-144: As a user in the editor, I want an Assign action that assigns the Layout being edited to the Display being edited in one click, so that the edit-assign loop is tight.

### Drag Session, Overlay, Snap, Span
- US-032: As a user, I want the Overlay to appear when I hold the Activation Modifier during a Drag Session, and to disappear when I release it, so that it never shows when I am just moving a window.
- US-033: As a user, I want the highlighted Zone to be the one under the cursor, not under the window center, so that aiming is precise.
- US-034: As a user, I want the Snap to happen only if the Activation Modifier is still down at mouse-up, so that releasing it first cancels.
- US-035: As a user, I want the Overlay drawn on every Display, including over a full-screen app on another Display where macOS allows it, so that I can aim across Displays.
- US-036: As a user, I want the Overlay to never take focus or interrupt my drag, so that the dragged window stays under my pointer.
- US-037: As a user, I want to hold the Span Modifier and sweep the cursor across Zones to Span them, so that a window can fill two or three Zones.
- US-038: As a user, I want the Span to be the bounding union of the swept Zones including the Gaps between them, so that the result is always one rectangle that looks like one wide Zone.
- US-039: As a user, I want a Snap to never move any other window, so that Zones snaps and never evicts.
- US-040: As a user, I want several windows to be allowed in one Zone, so that I can stack reference windows.
- US-041: As a user, I want a Drag Session started on a background window to work as well as on the focused one, so that I need not click first.
- US-042: As a user, I want a click on a title bar without movement to never arm a Snap, so that a Shift-click never moves my window.
- US-043: As a user, I want Caps Lock, Fn, or numeric-keypad state to never block the Activation Modifier from being recognized, so that the gesture is reliable.
- US-044: As a user, I want the Overlay to respect Reduce Motion and Reduce Transparency, so that it is comfortable with my accessibility settings.
- US-045: As a user, I want the Overlay to be invisible to VoiceOver, so that a visual aid does not add noise to VoiceOver output.
- US-046: As a user, I want the Overlay fill, border color, and opacity to follow my Appearance settings, so that it fits my setup.
- US-047: As a user, I want the Snap to tolerate apps that clamp their size and still place the window inside the Zone at its top-left, so that a stubborn app lands reasonably instead of looping.
- US-048: As a user, I want a Snap into a Chromium or Electron app to land without a slow animation or a silently ignored move, so that browsers behave like native apps.
- US-049: As a user, I want nothing to happen when the window I drag is full-screen, so that Zones never fights the full-screen Space.
- US-108: As a user, I want releasing the Span Modifier to freeze the accumulated Span rather than clear it, and re-pressing it to keep adding, so that I can let go of the key and still drop; releasing the Activation Modifier is the one way to clear it.
- US-109: As a user, I want the Span scoped to one Display and suspended, not cleared, while the cursor is on another Display, so that skimming a seam never throws away my sweep; a drop on the other Display uses the Zone under the cursor there.
- US-110: As a user, I want both modifiers held from the start of a drag to arm and begin the Span with the Zone under the cursor at that moment, so that key order does not matter.
- US-111: As a user, I want a second mouse-down, a right or middle button press, or a trackpad glitch during a Drag Session to be ignored, so that state never doubles or cancels by accident.
- US-112: As a user, I want the Overlay to vanish on mouse-up before any write begins, so that a slow app never keeps the Overlay on screen.
- US-133: As a user resizing a window by any edge or corner with the Activation Modifier down, I want no Overlay and no Snap, so that a resize is never hijacked.
- US-134: As a user with two same-size windows of one app stacked, I want the one I grabbed to move, and Zones to do nothing when it still cannot tell, so that it never moves the wrong window.
- US-135: As a user who snaps an already-snapped window to the same Zone, I want nothing to change and the Original Frame left alone, so that repeated chords are safe.
- US-136: As a user who switches Spaces mid-drag, I want the Overlay on the new Space, so that it is never stuck on the old one.
- US-137: As a user, I want the Overlay to follow a resolution or Dock change on its own, so that the Zones I see always tile the Display I am looking at.
- US-145: As a user, I want Zone Number labels drawn with a contrasting outline independent of the fill opacity, so that the shortcut legend stays legible at any Appearance setting.
- US-146: As a 3-Display user, I want a suspended Span to stay drawn on its Display in a dimmer style while the live highlight follows my cursor elsewhere, so that I can see what returning will resume.

### Shortcuts
- US-050: As a user, I want Control+Option+1..9 to send the focused window to Zone Number N on its Display, so that I can place windows without the mouse.
- US-051: As a user, I want Control+Option+Right/Left to cycle the focused window through Zones with wrap, starting from the Zone Zones last sent it to when it has not moved since, so that I can nudge it along even when the app clamped the size.
- US-052: As a user, I want Control+Option+R to Restore, Control+Option+E to open the editor, and Control+Option+Comma to open Settings, so that everything is reachable from the keyboard.
- US-053: As a user, I want to record any shortcut in a recorder that rejects combos lacking Command or Control and rejects a chord already bound to another Zones action, so that no action can silently never fire.
- US-054: As a user, I want a shortcut aimed at a Zone Number that does not exist, or at a window that is excluded, full-screen or unmovable, to do nothing and log why, so that nothing surprising happens.
- US-055: As a user, I want the editor and Settings shortcuts to work with no permission at all, so that I can always reach Settings to fix the grant.
- US-056: As a user, I want a shortcut registration failure (already taken by the system) to show inline in Settings, so that I know why a shortcut is dead.
- US-113: As a user, I want a failed re-registration to leave the previous chord active and any action to be left unbound, so that I can free a key without losing the others.
- US-114: As a user, I want cycling a window that matches no Zone to start at Zone 1 (Right) or the last Zone (Left), so that the first press is always defined.
- US-115: As a user, I want a shortcut or modifier change made in Settings to take effect for the next Drag Session without relaunch, and never mid-session, so that tuning is a tight loop that cannot race a drag.
- US-138: As a user, I want the window shortcuts to need Accessibility but never the mouse tap, and to be unregistered while the grant is missing, so that a chord is never swallowed from other apps for nothing.
- US-141: As a user who presses a window shortcut while a Drag Session is in progress, I want it ignored and logged, so that Zones never writes a frame while macOS is moving the same window under my mouse.

### Restore
- US-057: As a user, I want the Original Frame captured the first time a window Snaps and kept through later Snaps until I Restore or the window closes, so that Restore returns it to where it started.
- US-058: As a user, I want Restore by shortcut, so that one key puts a window back.
- US-059: As a user, I want a Drag Session with the Activation Modifier that ends outside the Display's visible area (menu bar or Dock strip) to Restore, so that there is a mouse path too.
- US-060: As a user, I want a plain drag without the Activation Modifier to never Restore, so that hand positioning is respected.
- US-061: As a user, I want Restore on a window that was never snapped to do nothing, so that the shortcut is safe to press anywhere.
- US-116: As a user, I want the keyboard path to capture the Original Frame on its first Snap exactly like the mouse path, so that Restore works after keyboard-only placement.
- US-117: As a user whose Original Frame is now off every Display, I want Restore to clamp it onto the nearest Display, so that the window never vanishes.
- US-139: As a user who Restores, moves the window by hand, and Snaps again, I want the next Restore to return to the hand-placed frame, so that Restore means "before the current round of snapping".

### Exclusions
- US-062: As a user, I want to exclude apps by bundle identifier from a list in Settings that shows the identifier beside the name, so that my terminal is never snapped and same-named apps are distinguishable.
- US-063: As a user, I want to add an Exclusion by picking from running apps or from a file picker, so that I need not know bundle identifiers.
- US-064: As a user, I want Zones to automatically skip sheets, popovers, non-standard windows, system dialogs, windows whose position cannot be set, and its own windows, and to place a fixed-size window at the Zone's top-left without resizing it, so that nothing unmovable shows an Overlay and fixed-size utilities still land.
- US-065: As a user, I want an excluded or skipped window to produce no Overlay at all during the Drag Session, so that the feedback is honest.

### Settings, Appearance, Launch at login
- US-066: As a user, I want a Settings window with General, Layouts, Shortcuts, Appearance, Exclusions, and About tabs, so that every option has a home.
- US-067: As a user, I want to pick the Activation Modifier and Span Modifier from Shift, Control, Option, Command, with the two forced to differ, so that the gesture cannot be made ambiguous.
- US-068: As a user, I want a Launch at Login toggle that reflects the real system status every time Settings appears, so that it never lies.
- US-069: As a user, I want a caption and a button to open Login Items Settings when macOS reports the item needs approval, so that I can finish enabling it.
- US-070: As a user, I want Launch at Login to be off by default and never auto-registered at launch, so that Zones respects my removal of it.
- US-071: As a user, I want a clear message when a dev or unsigned build cannot register for login, so that I know it is a build issue, not a bug.
- US-072: As a user, I want the About tab to show version, build, signing identity, license, and the single "inspired by FancyZones" line, so that attribution is honest and a lost grant after an ad-hoc update explains itself.

### Import and export
- US-073: As a user, I want to export all Layouts and Assignments, or one Layout, as a JSON document, so that I can back up or share them.
- US-074: As a user, I want to import such a document and choose Merge (default: keep mine, rename theirs) or Replace (a timestamped backup of both documents is written first and named), so that I control what happens and nothing is unrecoverable.
- US-075: As a user, I want an import of a newer-version document to be refused with a message naming the versions, so that nothing is silently mangled.
- US-076: As a user, I want an import whose Layouts fail validation (overlaps, gaps, bad ratios) to be rejected with the first offending Layout named, so that I can fix the file.
- US-077: As a user, I want an import to leave my files untouched if any part fails, so that a bad import is never half-applied.
- US-118: As a user, I want imported Assignments for Displays I do not have to stay dormant and apply when that Display appears, so that moving between desks is painless.

### Reliability, diagnostics, data
- US-078: As a user, I want Zones to never crash, hang, or beachball because a target app hung, so that a bad app does not take my window manager down.
- US-079: As a user, I want Zones to pause snapping an app for a short cooldown after it times out and then try again, so that one slow app does not get hammered.
- US-080: As a user, I want a corrupt data file to be moved aside with a timestamp and Zones to start with defaults and tell me, so that I never lose the file and never lose the app.
- US-081: As a user, I want a data file written by a future Zones version to be left alone and reported, so that downgrading does not destroy newer data.
- US-082: As a user, I want file writes to be atomic, so that a crash mid-write never leaves a half file.
- US-083: As a user, I want a "Copy Diagnostics" button that shows one paste-able text block (version, build, signing identity, macOS, permission and tap state, Displays, Assignments, preferences, recent events, skip counts) in a window before copying, so that a bug report is complete and I can see what I am sharing.
- US-084: As a user, I want diagnostics to never contain window titles or document names, so that pasting them is safe.
- US-085: As a user, I want the event tap to re-enable itself the moment macOS disables it, with a rate limit and a fallback to the permission window, so that dragging recovers without a relaunch and a dead tap never leaves a stale Overlay.
- US-086: As a user, I want Zones to keep working after I add, remove, rotate, or mirror a Display, without moving any window on its own, so that topology changes are calm.
- US-087: As a user, I want Zones to warn me once if "Displays have separate Spaces" is off, so that I understand why windows may straddle Displays.
- US-088: As a user, I want the Overlay to stay up with the highlight cleared and fills dimmed when the cursor is over the menu bar or Dock strip, so that I can see that a drop there Restores.
- US-089: As a user, I want preferences to carry a schema version and to lose only the one field that fails to decode, so that upgrading or downgrading never resets my shortcuts.
- US-119: As a user, I want a backup written before any document migration, so that an upgrade can never lose Layouts.
- US-120: As a user whose hand-edited preferences hold an unknown modifier or an invalid chord, I want only that field coerced to its default with a one-time notice, so that a bad value cannot disable the app or wipe the rest.
- US-121: As a laptop user, I want Zones to run no timers while idle except the trust poll while not granted and one five-second health tick while granted, and to poll the dragged window only until its move is confirmed, so that battery life is untouched.
- US-140: As a VoiceOver user, I want Enhanced UI restored after every write even when the write fails, and restored on next launch for apps a Zones crash left changed, so that Zones never degrades VoiceOver elsewhere.

### Maintainer stories
- US-090: As a maintainer, I want every rule (numbering, hit test, Span union, Snap plan, Exclusion decision, Drag Session transitions, cycle base) to be a pure function over value types, so that I can test it in milliseconds without a GUI.
- US-091: As a maintainer, I want AX, CG window listing, the event tap, Displays, hotkeys, login items, the Overlay, and the clock each behind one protocol with one production and one fake implementation, so that logic tests never touch the OS.
- US-092: As a maintainer, I want one and only one coordinate-conversion utility between AppKit, AX, and normalized Layout space, so that a flip bug is fixed in one place.
- US-093: As a maintainer, I want the whole logic suite to run with one command from the repository root and in CI on every ticket branch, so that regressions surface before merge.
- US-094: As a maintainer, I want strict-concurrency-clean code with no unchecked Sendable outside one documented window-handle box, so that data races cannot creep in.
- US-095: As a maintainer, I want every OS edge to return a typed result (applied, clamped, refused, timedOut, elementGone) rather than throw or crash, so that callers must handle each case.
- US-096: As a maintainer, I want the JSON documents to have golden fixtures per version and a migration test from each older version, so that format changes are deliberate.
- US-097: As a maintainer, I want the property-test generator to print the failing seed and the generated Layout in the assertion message, so that I can reproduce a failure in one run.
- US-098: As a maintainer, I want each ticket to name the protocol it implements, the fake it ships, and the tests it adds, so that a fresh agent can build it without reading the whole repository.
- US-099: As a maintainer, I want a manual test checklist for behaviors that need a human or a clean VM, so that releases verify the same things every time.
- US-100: As a maintainer, I want the app target to contain no `try!`, `as!` or `fatalError(` (per-line allow marker for the documented few), to import no AX or CG window API, and to hold no logic beyond wiring, so that the GUI layer is thin and boring and the rule is enforced by a gate, not by review.
- US-101: As a maintainer, I want the hot path (hit test, highlight) to allocate nothing per frame and never block on the WindowActor, so that 120 Hz drags stay smooth.
- US-102: As a maintainer, I want a structured logger with subsystem and category per module and an in-memory ring buffer feeding diagnostics, so that logs are searchable and bounded.
- US-122: As a maintainer, I want built-in Layouts to have deterministic identifiers derived from Template name and count, so that an Assignment can reference a Template without persisting it.
- US-123: As a maintainer, I want headless budget tests on the hot path (zero allocations, reducer throughput with an order-of-magnitude bound) and absolute timings only on the local checklist, so that CI never gains a flaky gate.

## Implementation Decisions

### Targets and dependency direction
- ZonesCore: value types shared by all (Layout, Node, Zone, Assignment, DisplayKey, PersistentDisplayKey, DisplaySnapshot, WindowHandle, Preferences), versioned document types, persistence with migration, Diagnostics (ring buffer, report builder), Logger facade, Clock protocol, the named-constants table. Knows nothing of AX or CG.
- ZonesLayout: split tree operations (split, merge, resize, validate), Templates, Zone Numbering, GeometryResolver, HitTester, SpanUnion, CycleResolver, the editor draft and command list. Depends only on ZonesCore. No AppKit.
- ZonesWindowing: protocol seams for the OS, the WindowActor, DragSessionReducer, SnapPlanner, WindowLedger, ExclusionPolicy, TopologyTracker, SessionAssignments, PermissionMonitor, the production AX and CG implementations. Depends on ZonesCore and ZonesLayout. The production adapter files are the only files that import ApplicationServices or the CG window-list API; a CI gate enforces it.
- ZonesTestSupport: seeded generator, Layout generators, fakes for every protocol, fixture loaders, the named fixture set.
- App: menu bar, Overlay panels, SwiftUI Settings and editor views, hotkey registrar, login item service, onboarding, wiring. No business rules.

### Protocol seams (one production, one fake each)
- WindowSystem: resolve elements at a point; read frame, role, subrole, fullscreen flag, settable flags; get and set enhanced UI; write frame following ADR-0022; observe destroyed for a handle; set messaging timeout. All inputs and outputs are Sendable value types. WindowHandle is an opaque Hashable struct whose production form wraps the retained AX element (equality by CFEqual, hash by CFHash) and is the single documented unchecked-Sendable box.
- WindowEnumerator: visible normal windows as WindowRecord (windowID, pid, bounds, layer, bundle identifier when known); describe a given set of window IDs; app-terminated notifications by pid.
- InputSource: two channels. Discrete events (mouseDown with point and window-under-pointer hint, mouseUp, flagsChanged, tapLost) are never dropped and keep order; mouseDragged is coalesced to the newest sample so a busy main actor never replays stale positions. Buttons other than the left are filtered at the source. Plus health (enabled, disabledCount) and start, stop, reenable.
- DisplayProvider: current snapshot array; AsyncStream of debounced TopologyChanged carrying before and after snapshots.
- OverlayPresenter: show a resolved OverlayModel (per Display: zone rects in Display-local points, labels, highlighted set with style, dimmed flag), update highlight, hide all.
- HotkeyRegistrar: register and unregister a Shortcut by action identifier returning a typed result; AsyncStream of fired action identifiers.
- LoginItemService: status, register, unregister, open settings.
- PermissionProbe: isTrusted, requestPrompt, openAccessibilitySettings.
- Clock: now and sleep, so cooldowns and debounces test instantly.

### Core types (shapes, not code)
- Node: either split(axis, ratio in open interval 0..1, first, second) or zone. The axis names the direction along which the two children are laid out: horizontal places them side by side (Columns), vertical stacks them (Rows). Leaves carry no stored number. Every leaf is a Zone.
- Layout: identifier (UUID), name, root Node, Margin points, Gap points (always explicit numbers, never inherited on disk), surround (normalized fraction per axis removed from each side before the tree is applied, default 0; the tree tiles the Layout rectangle that remains), origin (template name and count, or custom), modifiedAt. Built-in Layouts (every Template at every supported count) are generated at load with identifiers derived deterministically from Template name and count and with Margin and Gap from Preferences; they are read-only, never written to layouts.json, and may be referenced from assignments.json. Duplicate copies one into a custom Layout with a fresh identifier and the current default Margin and Gap written in.
- ZoneHit: zone(number), nearest(number), none. Facts only; policy lives in the reducer.
- ResolvedZone: Zone Number, normalized rect, points rect in visible-frame coordinates after surround, Margin and Gap, on the backing grid.
- DisplayKey: uuid(string) or unstable(vendor-model-serial string). PersistentDisplayKey holds only the uuid case and is the only key type the documents accept; an unstable key cannot be encoded by construction and the decoder rejects any other kind.
- Assignment: PersistentDisplayKey, Layout identifier, display name, last frame, visible frame and scale (for presentation and for editing a detached Display). Dormancy is derived at read time: a key absent from the current snapshot is dormant.
- SessionAssignments (memory only): DisplayKey to Layout identifier, consulted before the persisted document; holds picks for unstable keys and for a mirror group while mirroring; an entry is dropped when its key leaves the snapshot or mirroring ends.
- DisplaySnapshot: DisplayKey, frame, visibleFrame, scale, isMain, mirrorOf, separateSpaces flag.
- WindowRecord: windowID, pid, bounds, layer, bundle identifier. Never persisted; windowID is an in-session key only.
- SnapPlan: handle, target rect in AX coordinates, target Zone set and DisplayKey, position-only flag (size not settable), enhanced UI policy.
- FrameWriteResult: applied(actual), clamped(actual), refused(code), timedOut, elementGone, noOp (target equals current frame within tolerance).
- LedgerEntry: originalFrame; lastSnap (Zone set, DisplayKey, read-back frame) or none. Memory only, keyed by WindowHandle.
- Preferences: schemaVersion, activation modifier, span modifier, shortcuts map (every action optional), appearance (fill color, border color, opacity, default Margin, default Gap), exclusions set, enhancedUIPolicy, launched-before flag, warned-separate-spaces flag. Stored in UserDefaults under a namespaced key and decoded field by field with per-field defaults, so one bad value loses only that value.
- Named constants (one table in ZonesCore, each with a one-line rationale; tests reference names, never numbers): minimum Zone fraction 1/12, surround maximum 0.45, per-app AX timeout 250 ms, process-wide AX timeout 1 s, unresponsive cooldown 5 s, suspect window 3 s, relaunch gate three failures over 10 s, topology debounce 200 ms, tap re-enable limit 5 per minute, dead-tap retry 30 s, health tick 5 s, trust poll 1 s, frame-sample cadence about 60 Hz, candidate settle 3 samples, ring buffer 200 events, divider snap radius 6 points, usable-size warning 120x80 points.

### Documents and migration
- LayoutsDocument and AssignmentsDocument each carry a top-level integer version; the export document bundles both (or one Layout) under one version. Decoding dispatches on version: known older versions go through an ordered chain of migrations after the original is copied beside itself with the old version in the name; equal version decodes directly; higher version yields a typed refusal and the file is not touched.
- Corrupt file: rename aside with a timestamp suffix, start with defaults, emit a diagnostics event and a one-time user notice.
- Writes are synchronous and atomic (write temp, rename) on Save, on Assignment change, and on import. No debounce, nothing pending at quit.
- Import validation runs the same Layout validator as the editor; a failed import changes nothing on disk. Merge (default) keeps existing Layouts on identifier collision and renames incoming ones; Replace writes a timestamped backup of both documents, names it in the confirmation, then swaps both in one transaction. Assignments for keys not currently attached stay in the one map and take effect when the key appears.
- Preferences fields that fail validation (unknown modifier, equal modifiers, chord without Command or Control) are coerced field by field to defaults, logged, and surfaced once.

### Layout math
- Invariant enforced by the validator and property tests: leaves tile the Layout rectangle with no overlap and no gap; every ratio strictly inside 0..1; every leaf at least the minimum fraction on each axis; surround within its maximum per axis.
- Templates generate trees: Columns and Rows are right-leaning chains where the k-th of n-1 splits uses ratio 1/(n-k+1) so every Zone has equal extent; Grid is a tree of rows of columns; Priority Grid is three side-by-side Zones 25/50/25; Focus is a single leaf with surround 0.2 per axis (one Zone, Zone Number 1; see Challenges item 1).
- Zone Numbering sorts leaves by top edge then left edge in normalized space with an epsilon tolerance so rounding does not reorder visually aligned Zones. Numbers are recomputed on every read.
- GeometryResolver maps normalized rects to visible-frame points in one pass: apply surround, then Margin at the Layout edge; snap every divider coordinate once to the backing grid (1 divided by scale) and the Gap once to whole grid units; a Zone's edge at a divider is the divider minus floor(Gap/2) on the near side and the divider plus Gap minus floor(Gap/2) on the far side. Every Gap is identical in pixels, no remainder exists, nothing depends on traversal order, and the Overlay and the written frame are produced from the same output. A single ConversionUtility maps AppKit bottom-left to AX top-left global coordinates using the primary Display height, and maps an AX rect back to a Display by maximum intersection area.
- HitTester returns a ZoneHit: zone(n) for a point inside a resolved rect, nearest(n) for a point inside the visible frame but on surround, Margin or Gap (minimum edge distance, ties by lower Zone Number), none outside the visible frame. SpanUnion returns the bounding rect of a non-empty set, Gaps included.
- CycleResolver (pure): if the ledger holds a lastSnap whose read-back frame equals the current frame within one point, the base is that record (Right starts after its highest Zone Number, Left before its lowest); otherwise the base is the Zone with maximum intersection area with the current frame, ties to the lower Zone Number; no intersection yields Zone 1 for Right and the last Zone for Left. No observer is involved; a hand move is detected by the comparison.
- Merge in v1: siblings, plus two adjacent leaves within one same-axis chain of splits (deterministic re-chaining). Any other pair returns notSiblings with the hint "split the parent the other way first". General re-treeing is a spike, not a v1 ticket.

### Drag Session state machine (pure reducer)
- States: idle; pending(candidates up to two, downFrames, downPoint); moving(handle); armed(handle, display, highlighted set, span: set, displayKey, frozen flag, suspended flag).
- Events: mouseDown(point, hint), frameSample(handle, frame or timedOut), mouseDragged(point, flags), flagsChanged(flags), mouseUp(point, flags), windowGone(handle), tapLost, topologyChanged(snapshots), spaceChanged, wake. A mouseDown in any state but idle is ignored (logged once per session). Hotkeys are not reducer events; the dispatcher consults the reducer's idle flag.
- ExclusionPolicy runs in two phases so a bare click never costs an AX read. Phase 1 at mouseDown from CG facts only: ownWindow, systemBundle, userExclusion(bundle identifier), unresponsive (per-pid health). Phase 2 on the first returned frameSample from AX facts: nonStandardSubrole, sheetOrPopover, systemDialog, fullScreen, positionNotSettable. A candidate failing either phase ends the press as skip(reason) with no Overlay ever shown.
- Candidate resolution at mouseDown: event hint first, then front-to-back hit test of WindowRecords, then AX elements at point; a record and an element must agree on pid and on frame within one point. One agreeing candidate enters pending alone; two (stacked same-size windows) enter pending together and the first frameSample in which exactly one moved picks it; more than two, or two moving, or none settled after three returned samples with movement, ends the press as skip(ambiguousMatch). A first timedOut sample ends the press as skip(unresponsive) at once; the three-sample rule counts returned samples only.
- Frame samples are requested only in pending. pending to moving when a frameSample shows the origin changed and the size unchanged within tolerance; pending to idle on mouseUp (nothing recorded) or on any size change beyond tolerance (a resize, terminal for this press); pending stays pending while nothing moves. After moving nothing polls: the highlight follows the cursor and the Snap reads the frame once at mouseUp.
- moving to armed when flags contain the Activation Modifier; armed to moving when they do not (hideOverlay, span cleared). In armed, each mouseDragged updates the highlight: while the Span Modifier is down every zone hit on the span's Display is added and never removed; when it is up the set is frozen; re-press resumes adding to the same set; the set keeps its DisplayKey and is suspended while the cursor is on another Display (the live highlight there is the Zone under the cursor and the suspended set stays drawn on its Display in the secondary style) and resumes on return; both modifiers down at the arming sample begin the Span with the Zone under the cursor at that sample; the highlighted set always equals the set a mouseUp would snap to; a none hit clears the highlight and sets the dimmed flag.
- armed plus mouseUp with the Activation Modifier still down emits hideOverlay first, then snap(plan) for a non-empty span on its Display or a zone/nearest hit, or restore(handle) for a none hit. topologyChanged while armed re-arms from the new snapshots so Overlay and Snap share one geometry; while pending or moving it refreshes the snapshot and keeps state. spaceChanged re-asserts the Overlay. windowGone, tapLost or wake emits hideOverlay and returns to idle (no mouseUp can be trusted to arrive). moving or pending plus mouseUp returns to idle.
- Effects are values: showOverlay(model), updateHighlight(set, style, dimmed), hideOverlay, snap(plan), restore(handle), log(event). The App layer executes effects; the reducer never touches the OS. hideOverlay and the first snap or restore are emitted in the same reducer step as mouseUp.
- Modifier flags are masked to Shift, Control, Option, Command before comparison; the check is containment of the configured modifier; mouseUp consults the up-event flags.

### Snap engine
- SnapPlanner input: handle, current frame, target rect (one Zone or a Span union) in visible-frame points, target Zone set and DisplayKey, settable flags, EnhancedUIPolicy. Output: a SnapPlan, or noOp when the target equals the current frame within tolerance (nothing written, nothing recorded). Position-only when size is not settable, top-left aligned. The planner is pure; execution happens through WindowSystem on the WindowActor following the ADR-0022 order, skipping the enhanced UI pair when the attribute is absent or already off.
- On clamped(actual): if the accepted size exceeds the target, perform exactly one follow-up position write that aligns the window's top-left with the target's top-left while keeping it inside the visible frame. Never loop on clamping.
- On the first timedOut in a sequence: issue no further calls except the enhanced UI restore, mark the pid unresponsive, return timedOut. Worst case on the actor is two timeouts, not eight, so one hung app never blocks another app's gesture for long. refused: no retry, logged.
- WindowLedger (ZonesWindowing, keyed by WindowHandle, in memory only) is the single owner of LedgerEntry: it records the Original Frame on the first applied or clamped Snap from either the mouse or the keyboard path and never overwrites it; it records lastSnap (Zone set, DisplayKey, read-back frame) on every applied or clamped Snap; a successful Restore removes the entry so the next Snap is a first Snap again (see Challenges item 6); entries are removed on elementGone, on a destroyed notification, and for every handle of a pid on its app-terminated notification; no periodic sweep. Restore writes the recorded frame with the same write protocol; if the recorded frame intersects no current Display it is clamped onto the nearest Display's visible frame first.
- ExclusionPolicy (pure) decision: allow, or skip(reason) with the phase-1 and phase-2 reasons above; ambiguousMatch and unresponsive-by-sample are reducer outcomes that reuse the same skip log. Size-not-settable is not a skip; it becomes a position-only plan. Every skip reason is logged and counted in diagnostics.

### Shortcut dispatch
- Shortcut value: key code plus modifiers masked to the four real modifiers. Action identifiers: sendToZone(N), cycleNext, cyclePrevious, restore, openEditor, openSettings; every action may be unbound.
- ShortcutResolver (pure): given the focused window's read-back frame and flags, the ledger entry if any, the Display snapshots, Assignments (session first, then persisted), and the Layouts, it runs both ExclusionPolicy phases, then finds the Display by maximum intersection, resolves that Display's Layout fresh, and returns the target Zone (N, or the neighbor by Zone Number with wrap from the CycleResolver base). A missing Zone Number, a skipped window, or a full-screen focused window yields noOp(reason) and one diagnostics line.
- Dispatch: a window command that fires while the Drag Session reducer is not idle is dropped with one log line; editor and Settings commands always run.
- Registration: editor and Settings shortcuts are registered in every permission state; window shortcuts are registered on entering trusted and unregistered on leaving it, so a chord is never swallowed for nothing. On a Preferences change only shortcuts whose value changed are re-registered; while a Drag Session is not idle the diff is queued and applied on return to idle. A failed registration keeps the previous chord registered and reports inline. Duplicates among Zones actions are rejected in the recorder; conflicts with the system surface as a typed registration result shown inline. No built-in list of system chords.

### Overlay model
- OverlayModel is computed when an Assignment, Preferences appearance, or topology changes and cached: for each Display, resolved Zone rects converted to panel-local points, Zone Number labels, and style. Arm orders the pre-created panels front and sets the highlight; per mouseDragged only the highlighted set, its style (active or suspended) and the dimmed flag change. Panels and their layers are created at launch and rebuilt on TopologyChanged, ordered out when idle, never re-created per Drag Session; arm sets frames, colors and labels inside one transaction with implicit animations disabled and allocates nothing after warm-up. Labels are drawn with a contrasting outline independent of fill opacity and the correct contents scale per Display. Reduce Motion removes fades; Reduce Transparency switches to solid fills and draws the suspended style as an outline. No text beyond Zone Numbers. Panels and layers are not accessibility elements.

### Editor model
- The editor works on a draft copy of a Layout through a command list (split, merge, resize, setMargin, setGap, rename). Undo and redo are a command stack. The validator runs after each command; a failing command is rejected with a reason (tooSmall, notSiblings plus hint) and leaves the draft unchanged; the editor shows the resolved point size for the Display being edited and warns under the usable-size constant; Zones beyond nine are badged "no chord", never refused. Divider drags snap to halves, thirds, quarters of the parent and to collinear dividers within the snap radius, free with Option; arrows nudge one point (ten with Shift); H and V split the selection at one half; M merges the selection with its sibling when that sibling is a leaf or its same-axis chain neighbour, else shows the hint; ratios are stored as fractions. Assign sets the edited Display's Assignment to the draft's Layout in one click after Save. Save validates again, writes synchronously, and only then replaces the live Layout and the OverlayModel. Cancel discards the draft. The editor is a full-Display window on the Display being edited, drawing Zones where the Overlay will draw them; a Display switcher re-targets the draft (prompting when dirty); a detached Display is edited against its last snapshot from the Assignment in a window on the current Display.

### Launch at login
- LoginItemService is thin. The toggle derives its Bool from status equal to enabled only; it reads status on appear and on app activation; turning on registers (including from notFound); turning off unregisters; errors map to inline text; first launch never registers.

### WindowActor and resilience
- All WindowSystem calls run on one serial actor with the per-app messaging timeout and the process-wide timeout set at launch. Frame sampling uses a single in-flight sample at the sample cadence: a tick while a sample is outstanding is dropped, never queued. Sampling exists only in pending, so the actor is idle during the armed phase and a hung app cannot stall a live gesture.
- AX observers (destroyed only) live on one dedicated thread whose CFRunLoop runs; they forward value-type notifications to the actor, which owns no run-loop source. Moved and resized are not observed; nothing consumes them.
- A timedOut result marks that pid unresponsive for the Clock-driven cooldown during which ExclusionPolicy phase 1 reports skip(unresponsive). One retry after the cooldown. The cooldown belongs to the pid, never to the Drag Session. Heartbeat results feed only PermissionMonitor, never per-pid health.
- Enhanced UI toggling uses a defer-style restore even on failure and is governed by EnhancedUIPolicy (toggle, leave; default toggle per ADR-0022); the pair is skipped whenever the attribute is absent or already off, which is the only measurable signal and needs no bundle list. The pids whose enhanced UI Zones turned off are kept in memory and drained on every write path, on Quit and on entering revoked; a small recovery record (pid, bundle identifier, process launch date) is written asynchronously off the actor only on the set's transition from empty to non-empty, removed on clean quit, and on launch entries whose process still matches all three are restored. No disk write ever sits in a Snap sequence.
- elementGone results evict the handle from the ledger and any cache.

### Permission state machine
- States: unknown; untrusted(onboarding visible, or badge plus "Grant Accessibility" menu item when launched at login); trusted(tap running); suspect(tap recreate attempted, one trivial AX read pending); revoked(badge, onboarding visible, no relaunch button); needsRelaunch(same plus "Quit and Reopen").
- Signals: probe result each second while untrusted or revoked, no probe while trusted; tap creation returning nil; tap-disabled events handled in the tap callback itself (re-enable under the rate limit; beyond it tapLost at once, then an automatic retry on the dead-tap interval); any AX call returning the API-disabled code; one health tick while trusted that checks the tap is enabled as a watchdog and, only if the spike shows the signal is real, issues one trivial AX read of the system-wide element (one in flight, skipped during a Drag Session). Runtime signals move trusted to suspect; a successful recreate and read return to trusted; otherwise after the suspect window revoked. revoked moves to needsRelaunch only after the relaunch gate (three failed tap recreations over ten seconds with the probe reading true); a successful recreate from revoked returns to trusted. The probe alone never detects revocation of a running process. PermissionMonitor is the only place that decides revoked or needsRelaunch. "Reset and re-onboard" forces untrusted and re-runs the grant flow without touching documents or Preferences.
- Wake from sleep: re-validate the tap, re-poll once, force one TopologyChanged, order all panels out, end any Drag Session. Quit: disable and invalidate the tap, order panels out, drain the enhanced UI set, remove the recovery record.

### Launch sequence
- Set the process-wide AX messaging timeout; load documents (backup, migrate, or quarantine); load and coerce Preferences field by field; generate built-in Layouts; restore enhanced UI for matching recovery-record entries; register editor and Settings hotkeys; take the first topology snapshot and pre-create hidden panels; probe permission without prompting and, if trusted, start the tap and register window hotkeys, else onboarding; create the status item last so the menu never shows before state exists. Launched-at-login is detected from the launched-as-login-item flag on the open-application event, read only inside the did-finish-launching callback; on that path no window appears in any state (badge only when untrusted).

### Topology
- TopologyTracker consumes both AppKit and CG reconfiguration signals, debounces into one TopologyChanged, re-reads snapshots fresh, and publishes before and after. Assignment lookup consults SessionAssignments, then the persisted document; a returning uuid key restores its Assignment; an unknown uuid key gets the default; an unstable key gets the default until a menu pick stores a session entry. Mirror groups collapse to the mirror master (the member that mirrors nothing); while mirroring, picks go to SessionAssignments under the master's key and nothing is persisted; unmirror drops the entry and each member resumes its own saved Assignment. A Display whose UUID reads nil is retried on the Clock, then treated as unstable. Overlay panels and models are rebuilt on TopologyChanged and reused otherwise. No window is moved.

### Diagnostics and logging
- One Logger facade with subsystem and per-module category; the production sink is the unified log; the test sink is an array. A bounded ring buffer (permission and tap transitions, Snap results with pid, bundle identifier, Zone and write result, every skip reason, topology events) feeds the diagnostics report: app version, build and signing identity, macOS version, permission state, tap health, Displays with keys and frames, Assignments (session entries marked), Preferences, events, skip counts grouped by bundle identifier. The report is shown in a window before copying. Window titles are never read anywhere, so they cannot leak.

### Ticket graph rules
- Spike tickets first; each returns a verdict recorded as a short note. Decision tickets (Challenges 1, 5, 6, 7) precede the Templates, ExclusionPolicy, ledger and reducer tickets.
- Each module ticket is vertical: protocol, fake, pure logic, tests, and the production adapter where one exists. A ticket names its inputs by type and its outputs by protocol so a fresh agent needs only ZonesCore types plus its own ticket.
- The App wiring ticket is last and may only compose existing modules.

## Testing Decisions

### What a good test is here
- Exercises a pure function or reducer with value inputs and asserts on value outputs or emitted effects; no sleeping, no GUI, no OS calls; runs in under a few milliseconds; fails with a message that includes the seed or fixture name.

### Property tests (seeded generator, fixed seeds, failing seed printed)
- Tree tiling: for random trees of depth up to 8, leaf areas sum to the Layout rectangle, no two leaves intersect with positive area, every leaf meets the minimum fraction.
- Edit closure: split then merge returns the original tree; resize keeps the tiling invariant; random edit sequences never produce an invalid tree; same-axis chain merge yields a tree whose leaf set is the union.
- Numbering: numbers are a permutation of 1..N, stable under resize that preserves row order, and identical for trees that differ only by sub-epsilon edges.
- GeometryResolver: resolved rects stay inside the visible frame; every Gap measures exactly the same number of backing pixels and every edge lies on the backing grid for scales 1, 2 and 3; Margin, Gap and surround of zero reproduce the normalized rects scaled; the output does not depend on tree traversal order (mirror-image trees give mirror-image pixels).
- Templates: every Template at every supported count tiles and has the expected Zone count; Columns and Rows Zones have equal extent within epsilon; Columns 2 yields two Zones with equal top edges (axis convention golden).
- HitTester totality: every point in the visible frame maps to exactly one zone or nearest; every point outside maps to none; a point inside a resolved rect maps to that Zone.
- SpanUnion: result contains every member and equals the bounding rect.
- Conversion round trip: AppKit to AX to AppKit is identity across mock Display sets including a Display above and to the left of the primary (negative coordinates) and mixed scale factors.
- Reducer invariants: an Overlay is shown only in armed; every path to idle emits hideOverlay if one was shown, and hideOverlay precedes snap or restore in the same step as mouseUp; snap is emitted only with the Activation Modifier down at mouseUp; restore is never emitted from moving; the highlighted set equals the set a mouseUp would snap to; a Span Modifier release then re-press preserves the set; a Display change suspends and a return resumes it; any size change from pending ends the session; mouseDown outside idle changes nothing; no frameSample is requested after moving.
- Budget tests (headless, deterministic): HitTester, SpanUnion, GeometryResolver and Overlay arm allocate nothing after warm-up for a 9-Zone Layout; the reducer processes 10,000 synthetic mouseDragged events under an order-of-magnitude bound. Absolute timings live on the manual checklist.
- Document round trip: encode then decode is identity for random Layouts; migrations from each golden older fixture produce documents that validate; a Preferences blob with one unknown value loses only that value; an AssignmentsDocument containing a non-uuid key fails validation.

### Example and fixture tests
- Templates match golden normalized rects; Focus has one Zone numbered 1. Default shortcuts match ADR-0010. ExclusionPolicy table: each phase-1 and phase-2 reason, the bundle identifier path, size-not-settable yielding a position-only plan, and no phase-2 fact consulted before the first returned sample. Persistence: corrupt file aside-rename, higher-version refusal, atomic write under a failing fake filesystem, Merge renames, Replace backs up then swaps, no write pending after Save, Duplicate writes explicit Margin and Gap. Permission state machine: suspect to trusted, suspect to revoked after the window, revoked to needsRelaunch only after the gate with the probe true, the probe-stuck-true path, heartbeat API-disabled when enabled, tap-disabled handled at the callback with tapLost on the rate limit, Reset returns to untrusted with documents untouched. Idle scheduling: with the fake Clock, per permission state, exactly the named timers are scheduled and nothing else. TopologyTracker with injected snapshot sequences (add, remove, resize, mirror keyed by master with picks in SessionAssignments, unmirror restores each member, nil UUID retry, unstable key assignable in session and absent from the document, callback storm collapsed). WindowActor with a fake that delays beyond the timeout: result is timedOut, the sequence stops after the restore, cooldown is set, next call is skipped, retry occurs after the cooldown; a tick with a sample outstanding is dropped. SnapService against a fake element that clamps, refuses, times out, lacks enhanced UI, or has it off: restore on every path, pair skipped, one follow-up position write, noOp records nothing; the recovery record is written once on the first toggle and not again. CycleResolver: Calculator clamped at Zone 3 with a matching lastSnap cycles Right to 4; Span covering 1 and 2 with a matching lastSnap cycles Right to 3 and Left to the last Zone; a hand-moved window falls back to maximum intersection; no intersection starts at 1 or the last. Ledger: first-Snap-only capture from both paths; lastSnap updated on every Snap; Snap, Restore, hand move, Snap, Restore returns the hand-placed frame; app-terminated evicts every handle of that pid; clamp when the Original Frame intersects no Display. Reducer scenarios: click, modifier first, modifier late, release cancel, Span accumulate, freeze, resume, suspend across a seam with the secondary style, arm inside a Zone with both modifiers, arm on a Gap with both modifiers, drop in Gap (nearest), drop outside the visible frame (restore), edge resize from each edge, two stacked candidates resolved by the first moved sample, three candidates fail closed, first sample timedOut fails closed at once, pause before moving keeps pending, topologyChanged in pending keeps state, second mouseDown, window destroyed, tapLost hides the Overlay, right button absent from the stream. Dispatch: window command during a Drag Session dropped with one log line; registration diff queued during a Drag Session and applied on idle; failed registration keeps the old chord; window shortcuts absent while untrusted and registered on entering trusted. Preferences coercion table. Dormant Assignment applied when its key appears. Built-in Layout identifiers stable across runs. Modifier masking with Caps Lock, Fn and numpad bits. InputSource fake with a slow consumer delivers the newest dragged sample and every discrete event in order. Editor command stack: undo and redo round-trip, rejected command leaves the draft unchanged with its hint, M on a leaf sibling merges and on a split sibling hints, Save writes once, Cancel writes nothing, Assign after Save writes the Assignment, delete of an assigned Layout requires a replacement, a tenth Zone is badged not refused. Login toggle derivation table.

### Fakes contract and fixtures
- Every fake in ZonesTestSupport is scriptable: a queue of responses per call, a recorded call log, and optional latency driven by the fake Clock. HotkeyRegistrar and LoginItemService are seamed too, so toggle derivation and registration diffing are table tests. Fakes are the only test doubles; no ad-hoc mocks inside test files.
- Named fixture set: a 3-Display arrangement with the primary in the middle, a 2x Display on the left and a 1x portrait Display above; a hung-app fake that times out every call; an app fake that clamps to a 400x300 minimum; a window fake whose size is not settable; two identical Displays with serial 0; a mirror pair.
- Each production adapter has a thin contract test marked as manual that runs the same scenario against the real OS when a human invokes it, so fake and production drift is caught.

### CI gates
- Logic suite green from one root command; app build green with strict concurrency and zero warnings; a grep gate limited to `try!`, `as!` and `fatalError(` in the App target with a per-line allow marker; an import gate that permits ApplicationServices and the CG window-list API only in the production adapter files and forbids both in the App target; a fixture-hash test that fails when a golden document changes without a version bump; a test that every Template name matches CONTEXT exactly.

### Needs a human or a second machine
- Clean-VM TCC matrix on macOS 14, 15 and current: listen-only tap with Accessibility only, revocation mid-session and while idle (what the probe reads afterwards), re-grant, relaunch requirement. Self-signed identity keeping the grant across rebuilds. Login item status on a clean user account and from a DMG-mounted, quarantined copy. Overlay over full-screen Spaces, Split View, newly created Spaces, menu bar auto-hide, VoiceOver and Accessibility Inspector, 120 Hz frame pacing and arm latency in Instruments. Per-app matrix with wall time per Snap and enhanced UI side effects: Finder, Safari, Chrome, VS Code, Slack, IntelliJ, Terminal, System Settings, Calculator (position-only), a floating-panel app, a stopped app. 2x to 1x cross-Display Snap. Label legibility at ten percent fill opacity.
- One-page acceptance walk-through per release: grant from a clean account; Shift-drag across every Display and drop on a Zone, a Gap and the menu bar; Control-sweep a diagonal Span, release Control before the button, skim a seam and come back; send a window to each Zone by chord; cycle with wrap from a Span and after a clamped Snap; Restore, hand-move, Snap, Restore; revoke permission mid-drag and while idle; unplug a Display mid-session; change resolution mid-drag; mirror, pick a Layout, unmirror; import a document from another Mac with Merge and with Replace.

## Out of Scope
- Auto-update, cloud sync, iCloud, App Store distribution, localization beyond English.
- Re-snap or re-layout after Display topology changes; moving windows when a Display disappears.
- Tiling (evicting or rearranging other windows), window stacking order management.
- Per-Space Assignments unless the ADR-0013 spike passes; Space creation or navigation.
- Window title reading, Screen Recording, Input Monitoring.
- Any private API, any third-party dependency in v1.
- Per-window or per-app Layout memory across launches; the in-session lastSnap record is memory only and never persisted; snapping by window title or document.
- Windows-parity edge cases from FancyZones; special handling of Stage Manager; a built-in list of system chords.
- Text or hints on the Overlay beyond Zone Numbers; Escape to cancel (needs key tapping).
- General re-treeing merge (spike only); telemetry or network access of any kind.
- Observing moved or resized notifications; a hardware key kind persisted alongside the UUID.

## Further Notes

### Challenges to ADRs
1. ADR-0005 versus ADR-0003 and CONTEXT (Focus Template). A split tree whose every leaf is a Zone cannot express "one center Zone at 60 percent" while tiling the Display. Options: (a) three columns 20/60/20 (changes the user-visible Template to three Zones; Control+Option+1 hits a sliver); (b) inert leaves (a third leaf kind contradicting ADR-0003, ADR-0004 and the glossary, and a branch in every tree consumer); (c) a Layout-level normalized surround fraction applied before Margin, so the tree tiles the Layout rectangle, Focus is one Zone numbered 1, and a drop in the surround goes to the nearest Zone. Recommendation: (c), with a one-line amendment to ADR-0003 and CONTEXT ("tiles the Layout rectangle"). Decision ticket before the Templates ticket.
2. ADR-0021 (poll AXIsProcessTrusted to detect revocation). The probe does not reflect revocation of a running process (research); the tap returns nil after revocation and DTS says quit and relaunch. Refinement: keep the badge and re-onboard, derive revoked from runtime signals through a suspect state, keep the poll for the grant path, add needsRelaunch with "Quit and Reopen" only when the probe is true and tap creation still fails repeatedly. A probe reading false is reliable in the other direction: no relaunch button is ever shown while it reads false.
3. ADR-0009 ("ends outside every zone" Restores). With tiling Layouts, "outside every Zone" at render time is Margin, Gap, surround, or the strip outside the visible frame. Reading Margin and Gap as Restore makes an 8-point miss teleport the window. Decision: Margin, Gap and surround resolve to the nearest Zone; "outside every zone" means outside the Display's visible frame. Amend the ADR wording.
4. ADR-0022 (toggle enhanced UI on every write). The toggle is itself a write that can fail, race, or outlive a crash, and affects VoiceOver users. Refinement: restore in a defer on every path, skip the pair when absent or already off, persist touched pids across a crash (one asynchronous write per launch on the empty-to-non-empty transition, keyed by pid, bundle identifier and launch date to defeat pid reuse), and keep EnhancedUIPolicy (toggle, leave) so a default flip is not a rewrite. No behavior change in v1.
5. ADR-0018 (skip windows whose "size or position is not settable"). Research recommends writing position when only size is locked; fixed-size utility windows are what users park at a Zone's top-left and the position write is safe. Refinement: skip only when position is not settable; size-locked windows get a position-only plan. The ADR text should drop "size".
6. ADR-0009 (Original Frame kept until the window closes). Sequence Snap, Restore, hand move, Snap, Restore returns the pre-first-Snap frame, which users read as a bug. Refinement: a successful Restore removes the entry so the next Snap captures the current frame; "first Snap captures" and "forget on close" stay. Clearing on externally observed moves is rejected: it depends on observer cadence the research marks unverified.
7. ADR-0008 (span accumulation) is silent on Span Modifier release. Decision proposed: release freezes, re-press resumes, Activation Modifier release clears; the Span is scoped to one Display and suspended, not cleared, while the cursor is elsewhere. The FancyZones hysteresis rule (keep while inside the Span rectangle, replace outside) is rejected: the drop target would change with no key pressed and the reducer would carry a geometric region the user cannot see.
8. ADR-0012 (Displays identified by CGDisplay UUID). The UUID can read nil mid-reconfiguration and may collide for two panels of one model with zero serials. Refinement, not reversal: Clock-driven retry on nil; a vendor-model-serial fallback is an unstable key that accepts an in-session Assignment and is never persisted; the UUID remains the only persisted key.

### ADR-0013 contingency
- If the Space spike passes, Assignment gains an optional Space token and the AssignmentsDocument version bumps to 2 with a migration that leaves the token absent; the Overlay and ShortcutResolver already take an Assignment lookup so they do not change shape. If it fails, the token never exists and nothing is removed.

### Notes for the synthesizer
- Stories US-090 to US-102, US-122 and US-123 are maintainer stories; keep them as acceptance criteria on module tickets rather than as user-facing features.
- Stories US-103 to US-121 came from round 1; US-124 to US-140 from round 2; US-141 to US-147 and the revisions to US-004, US-023, US-030, US-051, US-085, US-100, US-110, US-121, US-128 and US-129 from round 3 (see Response log and the round-3 Steal list). Ids are stable.
- The reducer, planner, resolver, policy, ledger and tracker names above are interfaces, not file names; tickets may rename as long as each stays pure and fake-backed.
- Every tunable lives in the named-constants table; where this draft's numbers differ from the other drafts (minimum fraction, cooldown), pick one and keep the name.

### Open questions the spike tickets must answer
1. Does a listen-only tap for mouse and flagsChanged events work with Accessibility alone on a clean macOS 14, 15 and current VM, and what is its latency during a 120 Hz drag?
2. Does the self-signed "Zones Dev" identity keep the Accessibility grant across three rebuilds, and does reading modifier flags need no permission?
3. Does the window-under-pointer field of the mouse-down event equal the CG window ID, and does an AppKit window number equal its CG window ID on 14 and 15?
4. How often do AX moved and resized notifications fire during a live drag, and are window IDs stable across Spaces and full-screen?
5. What does window enumeration return with Screen Recording denied, and does the including-window option work alone?
6. Is the Overlay panel visible and the drag uninterrupted over a full-screen Space, a Split View Space, and a Space created after launch; do frontmost app and key window stay unchanged; what do frame and visible frame report with the menu bar auto-hidden?
7. Does one hidden witness window per Space identify the active Space reliably across Space deletion and full-screen (ADR-0013 gate)?
8. What is the timing order of the active-Space notification, the CG reconfiguration callback, and the AppKit Display-parameters notification during Space switch and Display reconnect?
9. Does the fullscreen attribute read true for a Safari full-screen window, and what do presentation options report there?
10. On a clean user account with a signed copy in Applications: login item status transitions, behavior from a DMG-mounted quarantined copy, and after the app is moved.
11. Per-app frame write behavior: which apps clamp, which ignore position without the enhanced UI toggle, which animate, and whether the stopped-app case returns timedOut within the per-app timeout.
12. Is SwiftUI hosting fast enough for static Overlay chrome at 120 Hz, or does the Overlay stay pure CALayer?
13. After revocation of a running process, what does the trust probe read, does an existing tap keep delivering events, and does a trivial AX read of the system-wide element return API-disabled promptly (gates the heartbeat)?
14. For two identical stacked windows, does the first frame sample after mouse-down move exactly one AX candidate, and within how many samples?
15. Do two identical Displays of one model report distinct UUIDs on the current release, and what does the fallback look like when their serials are zero?
16. On which thread do AXObserver callbacks arrive when the run-loop source is added to a dedicated thread, and do they keep arriving while that thread idles between drags?

## Response log
Round-2 critiques received from the power-user persona (PU-1 to PU-19) and the platform persona (PL-1 to PL-19). Earlier rounds' entries are folded into the draft.
- PU-1 (skip size-not-settable): ACCEPTED, already applied in the round-2 revision; US-064, positionNotSettable skip, position-only plan, Challenge 5 kept.
- PU-2 (Focus 20/60/20): ACCEPTED, already applied; Focus is one Zone numbered 1 via the surround fraction (Challenge 1).
- PU-3 (Span cleared on Display change): ACCEPTED, already applied; US-109 suspends and resumes.
- PU-4 (ledger keeps entry after Restore): ACCEPTED, already applied; Restore removes the entry (US-139, Challenge 6).
- PU-5 (relaunch offered while revoked): ACCEPTED, already applied; revoked and needsRelaunch are separate states (US-005); Challenge 2 now states the probe-false rule.
- PU-6 (idle revocation an hour late): ACCEPTED; US-004 now says badge at the first failed call or tap signal, and within five seconds only if the heartbeat spike passes.
- PU-7 (persistence debounce): ACCEPTED, already applied; synchronous atomic writes, no debounce.
- PU-8 (Preferences as one Codable value): ACCEPTED, already applied; field-by-field decode.
- PU-9 (US-088 "nothing visible"): ACCEPTED, already applied; Overlay stays, highlight clears, fills dim.
- PU-10 (unstable key with no in-session pick): ACCEPTED; US-128, SessionAssignments, Topology; unstable keys take a session-only Assignment and the pane says why.
- PU-11 (mirror key and persistence): ACCEPTED; picks while mirroring go to SessionAssignments under the master's key, nothing persisted, unmirror restores each member (US-147).
- PU-12 (grep gate on `!`): ACCEPTED, already applied; gate limited to `try!`, `as!`, `fatalError(`.
- PU-13 (Columns and Rows "equal ratios"): ACCEPTED; the k-th of n-1 splits uses ratio 1/(n-k+1); equal-extent property test added.
- PU-14 (US-055 shortcuts without permission): ACCEPTED, already applied; US-055 and US-138 split.
- PU-15 (warn versus reject duplicates): ACCEPTED, already applied; duplicates rejected, system conflicts via the registration result, no built-in chord list.
- PU-16 (resolver "else Zone 1" for both directions): ACCEPTED, already applied; Right starts at 1, Left at the last Zone.
- PU-17 (topologyChanged kills an armed drag): ACCEPTED, already applied; armed re-arms, and now pending and moving refresh the snapshot and keep state.
- PU-18 (editor ergonomics): ACCEPTED, already applied; US-129 to US-132, plus Assign (US-144) and the merge hint (US-023) this round.
- PU-19 (editor not at real scale): ACCEPTED; US-030 and the Editor model: full-Display window on the Display being edited, Zones drawn where the Overlay draws them.
- PL-1 (Focus): ACCEPTED, as PU-2.
- PL-2 (cooldown as a reducer state): ACCEPTED, already applied; no cooldown state, per-pid health in the WindowActor.
- PL-3 (Span cleared): ACCEPTED, as PU-3.
- PL-4 (topologyChanged to idle): ACCEPTED, as PU-17; only windowGone, tapLost and wake abort.
- PL-5 (edge resize rule): ACCEPTED, already applied; any size change from pending ends the session (US-133).
- PL-6 (two cycle rules; adopt the read-back record): ACCEPTED; one rule in CycleResolver, and the ledger now records lastSnap used only while the read-back frame still matches (US-051); no observer.
- PL-7 (persistence debounce): ACCEPTED, as PU-7.
- PL-8 (EnhancedUIPolicy auto by bundle list): REBUTTED; there is no auto case. The pair is already skipped whenever the attribute is absent or off, which is the measurable signal the critique asks for, so an auto case would be a third enum value with the same behavior as toggle.
- PL-9 (AXObserver on an actor without a run loop): ACCEPTED; observers (destroyed only) live on a dedicated run-loop thread and forward values to the actor; open question 16 added.
- PL-10 (US-088 wording): ACCEPTED, as PU-9.
- PL-11 (US-064 size-not-settable): ACCEPTED, as PU-1.
- PL-12 (DisplaySnapshot lacks scale): ACCEPTED, already applied; scale is in the snapshot and the grid tests run at 1, 2 and 3.
- PL-13 (unbounded AsyncStream): ACCEPTED, already applied; mouseDragged coalesced, discrete events never dropped.
- PL-14 (hotkey during a Drag Session): ACCEPTED; US-141 and the dispatch rule (dropped by the dispatcher, not a reducer event).
- PL-15 (mirror key unspecified, persistence while mirroring): ACCEPTED, as PU-11.
- PL-16 (AX reads on every click): ACCEPTED; ExclusionPolicy is two-phase, CG facts at mouseDown and AX facts on the first returned sample; a first timedOut sample ends the press.
- PL-17 (Preferences one Codable value): ACCEPTED, as PU-8.
- PL-18 (US-055): ACCEPTED, as PU-14.
- PL-19 (login detection unnamed): ACCEPTED; the launched-as-login-item flag on the open-application event, read only inside the did-finish-launching callback, is named in the Launch sequence.
