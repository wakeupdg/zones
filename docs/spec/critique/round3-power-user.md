# Round 3 critique — power-user persona

Lens: a 3-Display FancyZones veteran who drags fast, keeps six identical terminals open, binds chords by muscle memory, and reads every surprise during a Drag Session as a bug. Each attack quotes the story or section, says what breaks for that person (or contradicts an ADR or CONTEXT), and gives a fix the synthesizer can lift. Where the same defect appears in both drafts it is listed under each so neither can be closed without it.

## Attacks on platform

1. **US-038, US-052 and the reducer rows "span up, cursor inside union → kept" / "span up, cursor hits zone outside union → span = {zone}".** After I release Control my drop target changes with no key pressed: one Zone past the edge of a three-Zone Span and the sweep is gone, replaced by a single Zone, which is the "picture changes under my hand" that US-052 forbids. It also undoes US-124: a suspended Span resumes on return only if I re-enter through a member; re-entering through a neighbour replaces it. And it leaves three drafts with two release rules (power-user US-034 and maintainer US-108 freeze). Fix: release freezes the set, re-press resumes adding, Activation Modifier release clears; mis-sweep recovery is Shift up, Shift down. One Bool, one reducer row, no invisible hysteresis region.

2. **Reducer, "Pressed --frameSample: none or several moved after 3 samples--> Idle".** I grab a title bar, think for 60 ms, then drag: three samples pass with nothing moved, the session is over, Shift does nothing for that drag, and I retry twice before blaming the app. Fix: none moved keeps Pressed until mouseUp; only several moved after three samples, or any size change, ends the session. Scenario test: pause then move still arms.

3. **WindowResolver, "several are held until the first frame sample".** Uncapped. Five identical Terminal windows (one profile, one size) cost five AX frame reads per tick on the actor while I am only clicking around, and against a hung app five 250 ms stalls. Fix: cap the held set at four by z-order (two is too few for a power user's terminals); more than four fail closed before any sampling; one batched frame read per tick.

4. **US-056 and the reducer invariant "in Armed with hit none the highlight is empty and every fill dims".** The dim is the cue "release to Restore", but Restore happens only when an Original Frame exists; for a window never snapped the drop does nothing. The cue lies on the first window I ever drag to the menu bar. Fix: dim only when the registry has an entry for the dragged window; otherwise clear the highlight and leave the fills alone. The reducer input gains `hasOriginalFrame`; both branches are tested.

5. **US-059, Restore "clamp the frame onto the nearest Display".** The nearest Display to an off-screen rectangle can differ from the Display the window is on, so Restore jumps the window across Displays. Fix: clamp into the visible frame of the Display the window currently occupies (maximum intersection); "nearest" is only the tie-break when the window is on no Display.

6. **US-091 ("Margin and Gap in Appearance") versus `Preferences.appearance { color, opacity, labelsVisible }`, `Layout.margin: Points` non-optional, and read-only Templates.** No field holds a default Margin and Gap, so either the Appearance pane edits nothing or every Template is stuck at a hard-coded gap and I duplicate twelve built-ins to get my 8-point house style. Fix: Preferences carry default Margin and Gap; built-in Layouts are generated at load with them; a custom Layout's own values (nil means default) override; the pane says which Layouts it affects.

7. **`AssignmentsDocument { assignments, dormant, displays }`.** Two maps for one fact. Every dock and undock moves my entries between maps and rewrites the file; a crash between the two writes loses an Assignment exactly when I plug in. Fix: one map DisplayKey to record; dormant is derived at read time against the current snapshot.

8. **Launch sequence step 2 and HotkeyService, "register window hotkeys too, gated at dispatch".** Carbon registration consumes the chord system-wide whether or not the handler acts. Without the grant, Control+Option+1..9 and the arrows are dead in every app for nothing, and a user who never finishes onboarding loses eleven chords. Fix: window hotkeys are registered only in Granted and unregistered on leaving it; editor and Settings hotkeys always.

9. **SnapService, "up to eight round trips, so the hung-app worst case is 2 s on the WindowActor".** The actor is serial: 2 s on it means my next drag on a healthy app polls nothing and the Overlay is dead for 2 s. Fix: abort at the first `timedOut` (no further calls except the Enhanced UI restore), mark the pid unresponsive at once; worst case 0.5 s; a test asserts the call count after a timeout.

10. **Permission machine, `Revoked` always offers "Quit and Reopen" and retries every 3 s.** A transient tap failure under load puts a relaunch button in my face for 3 s that does nothing; a button that sometimes does nothing is a button nobody trusts, and the explanatory sentence is a tooltip for a design flaw. Fix: `needsRelaunch` as its own state, entered after three failed tap recreations over 10 s on the Clock with the probe reading true; `Revoked` shows badge, onboarding and Open System Settings only.

11. **Editor, "merge two sibling Zones".** In Columns 3 (a chain) Zones 1 and 2 are not siblings, so the most common merge a power user wants (two columns into one wide one) is refused with a hint to rebuild. Fix: siblings plus two adjacent leaves within one same-axis chain (deterministic re-chaining that preserves the leaf set); general re-treeing stays a spike.

12. **US-082 and `DisplayKey.unstable` "default Template, never persisted, explained".** Two cheap identical panels with zero serials lock me to Priority Grid for the session with no way out. Fix: an unstable key accepts an in-memory Assignment from the menu for this session; the Layouts pane says it will not be saved.

13. **No story for a drop on a Gap or Margin.** The behaviour (nearest Zone snaps) exists only as a reducer row and Challenge 2; a ticket can close with Gap drops Restoring and no story fails. Fix: a story: "a drop on a Gap or Margin snaps into the nearest Zone, never Restores".

14. **Reducer, "Pressed --frameSample: exactly one candidate moved, size unchanged, phase-2 policy passes--> Moving".** When phase 2 fails (sheet, full-screen, position locked) there is no row; the session is in no state and polling continues. Fix: `Pressed --one moved, phase-2 fails--> Idle` with the skip logged; polling stops; the Overlay never shows.

15. **Diagnostics report omits the signing identity.** "Lost the grant after updating" is the most common report ADR-0025 predicts, and the report cannot tell Developer ID from ad-hoc. Fix: app version, build and signing identity in the report and in About.

16. **US-062, cycle from `LastSnap` "when it has not moved since".** The research notes Chromium fires several resize notifications per write, so if the frame settles a point away after read-back, every cycle in Chrome falls back to intersection and the record is dead weight for the apps it was meant to help. Fix: either compare with a 2-point tolerance, or drop the record and use the max-intersection tie rule (several Zones tied means a Span: Right after the highest, Left before the lowest).

## Attacks on maintainer

1. **US-088, "highlight cleared and fills dimmed when the cursor is over the menu bar or Dock strip, so that I can see that a drop there Restores".** Same lie as platform 4: no Original Frame, no Restore, but the cue promises one. Fix: dim only when the ledger has an entry; reducer input `hasOriginalFrame`; both branches tested.

2. **US-117 and the ledger, "clamped onto the nearest Display's visible frame".** Display jump as platform 5. Fix: the Display the window occupies.

3. **Reducer, `pending(candidates up to two)`; "more than two ... yields skip(ambiguousMatch)".** Three identical Terminal windows (or any app that opens new windows at the same size) make the one I grabbed fail closed every time; a power user reads that as "Zones is broken in Terminal". Fix: cap at four by z-order; one batched read per tick; only "two or more moved" fails closed.

4. **CycleResolver, "Span covering 1 and 2 cycles Right to 2".** A window spanning Zones 1 and 2 pressed Right shrinks into Zone 2, half its width; no FancyZones user expects that, the next Zone is 3. Fix: when several Zones tie for maximum intersection within epsilon, treat them as a Span: Right goes after the highest tied Zone, Left before the lowest, with wrap. Pure, no stored placement; fixture test.

5. **Shortcut dispatch, "No built-in list of system chords" (also Out of Scope).** Carbon registration of Control+Up or Shift+Command+3 succeeds and the system swallows the chord first, so the recorder shows no conflict and the chord is silently dead, the failure US-053 says cannot happen. Fix: a data fixture of at most six chords (Mission Control, Spaces arrows, screenshot chords), labelled best effort and not maintained per OS release, surfaced as a warning that can be accepted.

6. **Editor stories US-022 to US-031 and US-129 to US-132: no one-click Assign.** Edit, save, close, open the menu, pick the Layout: five steps for the loop the editor exists for. Fix: an Assign action with a shortcut that assigns the draft's Layout to the Display being edited (platform US-139, power-user US-086).

7. **US-032, "Overlay to appear when I hold the Activation Modifier during a Drag Session".** CONTEXT defines a Drag Session as mouse-down to mouse-up, so this story says a Shift-click-and-hold on a title bar shows the Overlay, which US-042 forbids. Fix: "once Zones has confirmed the window is moving".

8. **Topology, "A Display whose UUID reads nil is retried after the next event".** If no further event arrives (one Display plugged, settles with nil, nothing else changes) the Display never gets a key or an Assignment. Fix: Clock-driven retry (three at one second) then the fallback key.

9. **Assignment record "display name, last frame and visible frame" has no scale.** Editing a disconnected 2x Display at its last size rounds on the 1x grid, and the ratios the editor shows differ from the live result. Fix: `lastScale` in the record; `DisplaySnapshot.scale` already exists.

10. **US-128, unstable keys "use the default Template with a note ... nothing persisted".** Same as platform 12. Fix: an in-session Assignment is allowed and labelled unsaved.

11. **Recovery file, "written only on the transition from empty to non-empty ... never sits between mouseUp and the first AX write".** When, then? The transition happens exactly when the first Enhanced UI toggle happens, which is between mouse-up and the first frame write. Fix: the record is written after the frame write sequence completes, as the tail of the same actor task; the Snap is never delayed by it; a crash inside that window is an accepted gap.

12. **US-136, "switch Spaces mid-drag → Overlay on the new Space".** Ungated promise: whether panels follow a Space created after launch is unverified in the research and the platform draft gates it on its spike 6. Fix: "where macOS allows it", visible result on the manual checklist.

13. **US-046 Appearance and the Overlay model: no legibility rule for Zone Numbers.** Numbers are the only shortcut legend; at 10 percent fill opacity on a bright wallpaper they vanish and nothing in the draft prevents it. Fix: labels drawn with a contrasting outline independent of fill opacity and the correct contentsScale per Display (platform US-147).

14. **US-054 (Zone N beyond the count does nothing) with no editor counterpart.** Nothing tells me while building a 4x3 that Zones 10 to 12 are unreachable by chord. Fix: badge Zones beyond nine with "no chord" in the editor (platform US-110); never refuse.

## Steal list

From platform (adopted into the power-user draft this round):
- Two-phase ExclusionPolicy: CG facts at mouse-down, AX facts at the first frame sample, so a bare click never touches the WindowActor.
- Window hotkey fired during a Drag Session is dropped with one log line (US-142).
- Zone Number labels with a contrasting outline and correct contentsScale (US-147).
- Editor badges Zones beyond nine with "no chord" and never refuses them (US-110).
- One 5 s health tick while granted folding the tap-enabled check and the spike-gated heartbeat; no separate 2 s watchdog.
- AX observers on a dedicated thread with a running CFRunLoop, forwarding value-type notifications to the actor.
- `DisplayKey` with a `hardware` tier persisted when unique among attached Displays, before `unstable`.
- ADR-0013 contingency: an optional Space token on Assignment and a version-2 document migration that leaves it absent.
- Re-enable rate limiter of about five per minute with backoff, then `dead` with an automatic retry every 30 s.

From maintainer (adopted):
- Merge of two adjacent leaves in one same-axis chain by deterministic re-chaining (US-023 refinement).
- "Exclude <App Name>" as a checkable menu item, checked when excluded, so the same click undoes it (US-126).
- Window shortcuts registered only while granted and unregistered on leaving it (US-138).
- Abort the write sequence at the first `timedOut`; worst case 0.5 s on the actor.
- `needsRelaunch` entered only after three failed tap recreations over 10 s with the probe true; poll schedule stated per state.
- Signing identity in About and in the diagnostics report (US-072, US-083).
- Enhanced UI recovery record written once per empty-to-non-empty transition, keyed by pid, bundle identifier and launch date.
- Other mouse buttons filtered at the InputSource, never emitted.
- Manual contract tests that run each production adapter against the real OS on demand, so fake and production cannot drift.
