# Round 2 critique — maintainer persona

Judged against the locked ADRs, CONTEXT.md, the research "Implications" and "Gotchas", and the question a maintainer asks of every rule: can a fresh agent test it headless in five years without reading the whole repository. Each attack names the story or decision, says why it fails, and gives a fix the synthesizer can lift.

## Attacks on power-user

1. **Focus as "inert leaves" (Layout model, Templates; C4).** A leaf that is not a Zone contradicts ADR-0003 (zones are the leaves), ADR-0004 (numbers over zones) and CONTEXT (a Zone is a region a window can be snapped into). Maintenance cost: every consumer of the tree (validator, numbering, HitTester, Overlay, editor split and merge, JSON schema, import validation) grows an `inert` branch and a test row, forever, for one Template. Fix: a Layout-level normalized surround fraction (default 0) applied before Margin; the tree tiles the Layout rectangle; Focus is one Zone, Zone Number 1; a drop in the surround resolves to nearest. File it against ADR-0003 and CONTEXT, not ADR-0005.

2. **Window registry `placement`, "cleared when an observer reports a move or resize that Zones did not issue", plus the "1 Hz resync while any WindowRecord has a placement".** Research says moved and resized notifications fire at gesture end and may not fire at all (unverified). State invalidated by an unreliable signal is stale by design. The resync is N serialized AX reads per second on the WindowActor (a hung app costs 250 ms each) and contradicts US-116 and US-117. Fix: store no placement. The cycle base is the Zone with maximum intersection area with the read-back frame (ties to the lower Zone Number); the registry holds only the Original Frame; observers serve `destroyed` only; delete the resync. Scenario test: Calculator clamped at Zone 3's top-left, cycle Right lands in 4 (the clamped window lies inside Zone 3, so max-intersection picks 3).

3. **US-034, the "Span release rule (FancyZones parity)".** After release the drop target depends on a hysteresis region (`spanRect`) the reducer must carry and the user cannot see; it conflicts with platform US-052 and with your own US-033 ("know what I will get before mouse-up"): the picture changes under the hand with no key pressed when the cursor exits the rectangle. Three drafts with three release rules is the actual defect. Fix: one rule: release freezes, re-press resumes, Activation Modifier release clears; mis-sweep recovery is Shift up, Shift down. Freeze is one Bool in the state and one reducer test row.

4. **`WindowRecord { key: WindowKey (pid + AX element hash), originalFrame, placement }` in ZonesCore.** ZonesCore must not know AX exists (ADR-0002 puts AX behind ZonesWindowing). The name collides with the CGWindowList record `(windowID, pid, bounds, layer)` that the research calls the window model. An element hash as identity is not identity: CFHash collides, which is why Rectangle carries a synthetic-id fallback. Fix: ZonesCore defines an opaque `WindowHandle: Hashable, Sendable`; its production form in ZonesWindowing wraps the retained element and defines equality by CFEqual; the ledger lives in ZonesWindowing and is named for what it stores (Original Frames).

5. **Editor merge via "re-treeing" (`merge` returning `notExpressible`; C3).** The algorithm is unspecified, your own open question doubts it is simple enough for v1, and `notExpressible` is an error no user can act on. A rule whose outcome depends on a search is hard to test exhaustively and impossible to explain in a tooltip. Fix: v1 merge is siblings (ADR-0003) plus the deterministic case of adjacent leaves within one same-axis chain (which yields a wide center from three columns); general re-treeing is a spike with a decision table over Template-derived trees and lands as its own ticket or not at all.

6. **US-115 ("Snap completes within 50 ms of mouse-up").** The number belongs to the target app, is unmeasurable headless, and fails in Chrome under load whatever Zones does. Fix: budget Zones' own work: `hideOverlay` and the first `snap` effect are emitted in the same reducer step as mouseUp (a headless assertion); per-app wall time is a column in the manual matrix.

7. **US-116 and US-117 versus "any 1 Hz resync runs only while at least one WindowRecord has a placement".** A power user with twenty windows always has a placement, so the resync always runs, so "no polling at all while idle" is false every day. Fix: delete the resync (attack 2) and enumerate the idle wake-ups in the story: trust poll while not granted, tap health check, nothing else.

8. **Permission machine: `revoked` to `needsRelaunch` "with trust reading true while the tap still fails".** Research says the probe does not reflect revocation of a running process, so it may read true for the whole revoked period; every tap failure, including a transient one under load with the grant intact, then goes straight to "Quit and Reopen". The draft also never says whether the poll runs in `revoked` ("While granted there is no poll"). Fix: define the probe schedule per state (poll in notGranted and revoked only); enter `needsRelaunch` only after K failed tap recreations over a Clock window with the probe true; add a reducer test for "probe stuck true"; record what the probe reads after revocation in the manual checklist.

9. **`moving` "entered when the polled frame shows the origin moved with size unchanged. Size change with origin fixed is a resize".** Still wrong after round 1: a top or left edge resize changes origin and size, matches neither clause, and is treated as a move, so US-027 fails. Fix: any size delta beyond tolerance ends the session; a move is origin changed and size unchanged.

10. **US-041 (scale factor sizing).** Still in the draft after the round-1 attack: AX frames are in points, so scale cannot change the result; the real hazard is clamping to the source Display, already covered by the size-position-size order. A tester hunts a bug that cannot exist. Fix: reword to the clamp hazard; keep the 2x to 1x case as a manual matrix row.

11. **Shortcut recorder "small built-in list of macOS chords".** The list drifts with every macOS release and ignores the user's own remaps in Keyboard Settings; it will be wrong silently and nobody will own it. Fix: either drop it and rely on the inline registration result, or ship it as a data fixture (not code) of at most six chords with a test, with the story saying "a short list, best effort" and the ticket saying it is not maintained per OS version.

12. **Overlay "Zone layers are rebuilt from `resolve` on each arm" with the budget "layer rebuild for every Display under 4 ms".** Layer allocation per arm is hot-path allocation (ADR-0023: create once, reuse), and 4 ms is an absolute timing no headless test can hold. Fix: the OverlayModel and its layers are rebuilt on Assignment change and TopologyChanged; arm only orders panels front and sets the highlight; the budget becomes "zero allocations on arm after warm-up" plus a manual Instruments row.

13. **`assignments.json { version: 1, assignments: [DisplayUUID: LayoutID] }` versus US-138 and the Layouts pane (disconnected Displays with name, resolution, last known size).** The document has no field for any of that, so either the pane reads from nowhere or version 1 ships incomplete and needs a migration in week two. Fix: version 1 carries per-DisplayKey metadata (name, last frame and visible frame) beside the Layout identifier, used for presentation and for editing a detached Display.

14. **Performance budget tests "under 20 microseconds" and "under 50 ms" as headless CI gates.** Absolute wall-clock bounds flake on shared runners and get deleted within a month. Fix: CI asserts zero allocations after warm-up and an order-of-magnitude bound (10,000 events under 2 s); microsecond timings are a manual checklist row.

15. **US-008 ("stable code signature so the grant survives updates").** ADR-0025 lets a release fall back to ad-hoc signing; an ad-hoc release changes its hash on every build, so the grant drops on every update and the story is false for that path. Fix: scope the story to Developer ID-signed releases; the release script warns loudly when ad-hoc; the diagnostics report includes the signing identity so a "lost grant after update" report explains itself.

16. **US-144, Copy Diagnostics copies without showing.** The report lists bundle identifiers (Exclusions and recent Snaps), which is the user's app inventory. Fix: show the report in a window before copying (platform US-132).

17. **Exclusion decisions spread across the `pressed` prose, the window service ("a window whose position is not settable is skipped") and US-145's reason list.** Three places, no type. Fix: one pure ExclusionPolicy returning `allow | skip(reason)` with the enumerated reasons, evaluated before any Overlay effect, with one table test per reason.

## Attacks on platform

1. **US-136 and the idle budget: "a 5 s permission heartbeat" (one trivial AX read while granted).** Unverified by your own open question 14: if the read keeps succeeding after revocation of a running process, this is a permanent timer carrying no information; if the focused app is hung it costs up to 250 ms on the actor every 5 s. Fix: the heartbeat is a spike-gated PermissionMonitor input, off by default, enabled only if the spike shows `apiDisabled`; when on, one in flight, skipped during a Drag Session, reading the system-wide element only.

2. **OriginalFrameRegistry "1 Hz sweep that runs only while the registry is non-empty".** The sweep's work is unspecified. If it reads AX per handle, twenty snapped windows cost twenty serialized actor calls per second and a hung app stalls the actor 5 s per sweep. Fix: evict on `uiElementDestroyed` and on `elementGone` from a real call only; if a sweep is kept it checks pid liveness via the process table, never AX, and the decision says so.

3. **SnapService "up to eight round trips, so the hung-app worst case is 2 s on the WindowActor and never on the main thread".** "Not on the main thread" is not "never freezes": the actor is serial, so a 2 s stall blocks frame polling of the next Drag Session and every shortcut. Fix: abort the sequence at the first `timedOut` (issue no further calls), mark the pid unresponsive at once, run only the EUI restore as follow-up; the worst case becomes 0.5 s and a test asserts the call count after a timeout.

4. **WindowResolver: "several candidates are held until the first frame sample, and the one whose frame changed wins".** Unbounded N: five same-size windows of one app means five AX reads per tick during Pressed. Fix: cap the candidate set at the top two by z-order; more than two fail closed (`ambiguousMatch`) before any sampling.

5. **Drag reducer: `Pressed --frameSample: none or several moved after 3 samples--> Idle`.** A user who grabs a title bar and pauses 50 ms before moving (three samples at 60 Hz) ends the session; the later move never arms and the Overlay never shows for that drag. Fix: "none moved" keeps Pressed until mouseUp; only "several moved" after 3 samples, or any size change, ends the session.

6. **DisplayTopology: "no Assignment is persisted while mirroring is active" beside "mirror sets collapse to the mirror master".** Pick a Layout from the menu while mirroring and it vanishes on unmirror. The master's key is a stable UUID, so the no-persist rule protects nothing. Fix: persist under the master key; delete the rule.

7. **`AssignmentsDocument { assignments, dormant, displayNames }`.** Dormancy is derived (key absent from the current snapshot), not state. Two maps mean every unplug and replug rewrites the file and migrates entries, and a crash between the two moves loses one. Fix: one map DisplayKey to (Layout identifier, name, last frame); "dormant" is computed against the current snapshot at read time.

8. **Permission: `Revoked -> NeedsRelaunch (poll returns true while tap creation still fails)`.** Same hole as the power-user draft: if the probe reads true throughout (research), Revoked lasts one tick and a transient tap failure becomes a relaunch prompt. Fix: K failed recreations over a Clock window (3 over 10 s) plus probe true; a test for the probe-stuck-true path; the manual checklist records the probe's actual post-revocation value.

9. **Cross-cutting "Enhanced UI safety: the set of pids ... written to a small recovery file before the write and cleared after".** A synchronous atomic file write sits between mouse-up and the first AX write on every Snap, contradicting US-053's two-millisecond budget; and a pid in the file may belong to another process after a crash and reboot. Fix: write the file only on the transition from empty to non-empty (first app touched since launch), key entries by pid plus bundle identifier plus process launch date, remove the file on clean quit, and on launch restore only entries whose process still matches all three.

10. **`WindowHandle` "is the CFHash of the AX element plus pid".** A hash is not identity: two live windows can collide and silently share one Original Frame. Fix: the handle wraps the retained element inside the one unchecked-Sendable box; equality is CFEqual, hash is CFHash; the registry keys on the handle.

11. **Testing: "every module above except InputTap, OverlayController rendering, HotkeyService and LoginItemService has a protocol boundary with a scriptable fake" versus the listed tests "registration diffing re-registers only changed shortcuts; changes during a session are deferred" and the login toggle rules.** Those tests need the seams the sentence excludes. Fix: seam HotkeyRegistrar and LoginItemService (thin protocols, trivial fakes); the exclusion list shrinks to InputTap and panel rendering.

12. **HotkeyService: "register window hotkeys too, gated at dispatch by PermissionState".** Carbon hotkeys consume the chord system-wide whether or not the handler acts, so a user without the grant loses Control+Option+1..9 in every app for nothing. Fix: window hotkeys are registered only in Granted and unregistered on leaving it (registration diffing already handles the churn); editor and Settings hotkeys stay registered always.

13. **Stores: "Writes are synchronous and atomic ... no debounce; flush on quit".** "Flush on quit" implies a buffer that "synchronous" denies. Fix: delete "flush on quit"; the test is "after Save returns, the file on disk decodes to the saved document".

14. **US-083 (identifier changed after a firmware update, one-click offer of the vanished Display's Layout).** Still present after round 1: Zones cannot tell a changed UUID from a new Display, so the offer is a heuristic that fires for every borrowed projector. Fix: the Layouts pane lists disconnected Displays with "Copy Assignment to <attached Display>" and "Forget"; no heuristic.

15. **US-079 (Stage Manager: "never touch recent-apps thumbnails") versus Out of Scope ("no special handling of Stage Manager").** A story promises what scope disclaims and no test can hold it. Fix: drop the story; keep open question 11 and the manual row.

16. **Preferences `appearance: { color, opacity, labelsVisible }` and US-091 ("Margin and Gap in Appearance") versus ADR-0003 (Margin and Gap are per Layout) and read-only Templates.** Which Layout's Margin does the Appearance pane edit, and how does a user get Gap 0 on a Template without duplicating it? Fix: Preferences hold a default Margin and Gap; built-in Template Layouts are generated at load with those values; custom Layouts carry their own, edited in the editor; the Appearance pane says "applies to Templates and new Layouts".

17. **LayoutEngine property "every pair is separated by exactly Gap and the outer edge by exactly Margin" together with "rounded to the backing grid".** Exact equality fails whenever Gap or Margin is not a multiple of 1/scale (Gap 7 at scale 3): a flaky property. Fix: assert within half a backing pixel; assert exactness only for values that lie on the grid.

18. **Menu "Exclude <frontmost app>".** An immediate, global action with no confirmation and no undo from the menu. Fix: render it as a checkable item ("Exclude <App Name>", checked when excluded) so the same click undoes it; no alert needed.

## Steal list

From power-user (folded into the maintainer draft as US-124 onward or as revisions):
- Editor ergonomics: single-key split, divider snapping to halves, thirds, quarters and collinear dividers with a free-drag modifier, arrow nudging, live Zone Numbers in the editor, Display switcher, save and close shortcuts (US-077, US-078, US-079, US-084, US-085, US-088).
- Exclusions by running-app picker or file picker, bundle identifier shown beside the name (US-093, US-096).
- Menu picker names Templates with their Zone counts ("Columns 3"); the chord range is visible without the editor.
- Settings and the editor open on the Display under the cursor (US-118); modifiers shown as key caps in General; cheat sheet at the end of onboarding (US-113).
- Layouts pane lists disconnected Displays with "Copy Assignment to" and "Forget"; a detached Display's Layout is editable at its last known size (US-138).
- Snap is idempotent: same Zone again changes nothing and never touches the Original Frame (US-112).
- Modifier and appearance changes apply to the next Drag Session without relaunch (US-119).
- Shortcuts do nothing when the focused window is excluded, full-screen or unmovable (US-067).
- Restore after a Span works exactly as after a Snap (US-054); export of a single Layout as well as all (US-097).

From platform:
- Candidate disambiguation in Pressed by the first moved frame sample (US-023), adopted with a cap of two candidates.
- Resolved rects rounded to the backing grid with the remainder carried to the last Zone per axis; `scale` on DisplaySnapshot (US-049).
- `DisplayKey = uuid | unstable`; an unstable key uses the default Template and is never persisted (US-082).
- Preferences decoded field by field with per-field defaults (US-104).
- Mirror sets keyed by the mirror master (US-076).
- Diagnostics shown in a window before copying (US-132).
- A successful Restore removes the Original Frame so the next Snap re-captures (US-126), filed as a challenge to ADR-0009.
- EUI toggle pair skipped when the attribute is absent or already off; the recovery file for EUI across a crash (US-116), adopted with the write-once-per-transition rule from attack 9.
- Space switch mid-drag re-evaluates the Display and re-asserts panels if the spike shows the need (US-029).
- Template menu-bar icon; Settings opens on the current Space and becomes key (US-097, US-098).
- Window command path reads everything fresh and writes one diagnostics line per silent no-op.
- `hideOverlay` and the first `snap` effect emitted in the same reducer step as mouseUp, as a headless test.
- Discrete input events (down, up, flagsChanged) on a never-dropped channel; dragged coalesced to the newest sample (round-1 attack 5).
- Grep gate limited to `try!`, `as!` and `fatalError(` with a per-line allow marker.
- Suspect state with a 3 s window, and `needsRelaunch` as a state distinct from `revoked`.
