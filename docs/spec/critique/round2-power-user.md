# Round 2 critique — from the power-user persona

Scope: attacks on the platform and maintainer drafts as revised after round 1, from the lens of a 3-Display FancyZones veteran: speed, predictability, zero surprise during a Drag Session, multi-Display and multi-window flows, shortcuts that never collide, an editor faster than numbers. Judged against the locked ADRs, CONTEXT.md and the research Implications and Gotchas. Each attack quotes the story or decision, says why it fails, and gives a fix the synthesizer can lift.

## Attacks on platform

1. **US-046 ("visible area read fresh at drop time") contradicts US-049 ("what I saw is what I get").** OverlayController computes the model once per arm; if `visibleFrame` changes between arm and drop (Dock resized, auto-hide toggled, a reconfiguration mid-drag), the Zone drawn and the Zone written differ and the window lands where the Overlay never showed it. Fix: the drop uses the snapshot the Overlay was drawn from; a `TopologyChanged` while `Armed` re-arms from the new snapshot (redraw, re-hit) so Overlay and Snap always share one geometry. Strike "read fresh at drop time".

2. **`resolve` rounds "to the backing grid with the remainder carried to the last Zone per axis".** On Columns 5 the fifth column is a pixel wider than its siblings, label centring differs, and "last" depends on traversal order, so a mirror-image Layout rounds differently. Fix: round shared edges, not sizes. Each divider coordinate is snapped to the backing grid once; neighbours share the rounded edge, so there is no remainder, no seam and no order dependence. Tiling property tests run on unrounded output; a second test asserts every rounded edge lies on the grid.

3. **Span freeze (US-038, US-052) has no highlight rule in the reducer.** `Armed --span up--> Armed(span.frozen = true)` says nothing about what is lit; the invariant "highlighted set equals the set a mouse-up would snap to" sits in the maintainer's tests, not here. A frozen three-Zone Span with the cursor parked on a fourth Zone either lights the Span (correct) or the cursor Zone (the Overlay lies). Fix: highlight = `spanRect` when the Span is non-empty and the cursor is on its Display, else the Zone under the cursor; add the invariant to the reducer property tests.

4. **US-124 (Span suspended on another Display) gives no visual cue.** The cursor skims a seam, the highlight jumps to a Zone on Display B and the three-Zone Span on Display A disappears from view; the user cannot tell whether going back resumes it. Fix: a suspended Span stays drawn on its Display in a secondary (dimmer) highlight style while the active highlight follows the cursor; Reduce Transparency draws it as an outline instead of a second alpha.

5. **Cycle "from the Zone whose rect best matches the read-back frame" is undefined for a Spanned window.** A window filling Zones 1 and 2 matches neither; equal ratios make Right from a Span nondeterministic. Fix: match = largest intersection area with the window frame, ties by lowest Zone Number; from a Span whose members tie, Right goes to the Zone after the highest member and Left to the Zone before the lowest. Table-test it.

6. **US-068 and HotkeyService report only Carbon registration failure.** Global hotkeys beat app shortcuts, so Command+1 registers as `applied`, never `conflict`, and the user silently loses tab switching in every browser and terminal; Mission Control and screenshot chords register fine and then fight. Fix: the recorder warns (accept allowed) on Command+digit, Command+arrow and a small built-in list of macOS chords; registration failure stays a separate `conflict`. Tell me before, not after.

7. **US-111 (edit a detached Display at its last known size) still has no data.** `AssignmentsDocument { version, assignments, dormant, displayNames }` carries names only; the maintainer's round-1 attack 7 was not applied. Fix: add `lastFrame` and `lastVisibleFrame` per DisplayKey (the power-user revision does this), or drop the story.

8. **`DisplayKey.unstable` "uses the default Template and is never persisted" leaves two identical panels on Priority Grid forever.** Many 1080p panels report serial 0; the user cannot pick Columns 3 for either, even for the session. Fix: an unstable key accepts an in-session Assignment (memory only), the Layouts pane labels it "not saved: no stable identifier", and the menu picker works as usual.

9. **US-091 puts Margin and Gap in Appearance; US-105 puts them in the editor per Layout.** ADR-0003 makes them Layout-level values and Templates are read-only, so where do a Template's Margin and Gap come from, and does changing Appearance rewrite every custom Layout? Fix: Appearance holds the default Margin and Gap used by Templates and by new custom Layouts; a custom Layout's own values override and are edited in the editor; the preview says which applies.

10. **US-079 (Stage Manager) is still a promise.** Round-1 attack 6 asked for a checklist row gated on spike 11; the revised story promises "never touch recent-apps thumbnails" with no research behind it. Fix: Out of Scope, keep the cross-cutting "no special casing" note, and a manual row: drag under Stage Manager, confirm resolved window and Overlay level.

11. **PermissionMonitor heartbeat results can poison per-app health.** The 5 s heartbeat runs on the WindowActor, which turns `timedOut` into `AppHealth.unresponsive`; if the read is attributed to the focused app on a busy machine, the next drag on that app shows no Overlay for ten seconds for no visible reason. Fix: heartbeat results feed only PermissionMonitor (`apiDisabled` or not), never `AppHealth`; test it with the fake.

12. **Menu "Exclude <frontmost app>" is one click with no confirmation.** With Finder frontmost a slip excludes Finder, and every Finder drag then shows nothing (US-088) until the user finds the Exclusions pane. Fix: the item reads "Exclude <App>..." and confirms with the bundle identifier, or the next menu open shows "Include <App> again" in the same slot for one session.

13. **US-053 ("under two milliseconds between mouse-up and the first write") spans two executors.** `hideOverlay` and `union` run in the reducer step on the main actor; the registry lookup and the write run on the WindowActor; one test cannot assert the sum. Fix: assert what the reducer step emits (hideOverlay first, then a snap plan with a fully resolved target rect) in the same step as mouse-up; the actor hop is a manual timing row.

14. **US-032 ("Zone resolved on the Display under the cursor at mouse-up") versus `display(for axRect)` by maximum intersection.** When the cursor is on Display B and the dragged window still straddles A and B, the reducer never says which Display's `visibleFrame` the `none` check uses; maximum intersection would pick A. Fix: hit testing and the `none` check use the Display under the cursor, never the window's Display; the write converts into that Display's coordinates.

15. **`Pressed --frameSample: none or several moved after 3 samples--> Idle` on a hung app.** Each sample times out at 250 ms, so three take 750 ms, during which the user has dragged across the Display with Shift held and seen nothing. Fix: the first `timedOut` sample in `Pressed` ends the session as `unresponsive` and logs the skip; the three-sample rule applies only to samples that return.

## Attacks on maintainer

1. **US-064 skips "windows that refuse resizing" and ExclusionPolicy has `notSettable` as a skip.** This is the literal ADR-0018 text that both other drafts challenge with research (ax-window-moves, implications 2 and 3): Calculator, inspectors and fixed-size utility windows never get an Overlay. Round-1 attack 6 from platform was not applied. Fix: skip only `positionNotSettable`; `sizeNotSettable` becomes a position-only SnapPlan aligned to the Zone's top-left; add the ADR-0018 refinement to Challenges.

2. **Focus as three columns 20/60/20 with the centre as Zone Number 2.** A Template named for one Zone shows three; Control+Option+1 sends my editor to a 20 percent sliver; the Overlay for "Focus" looks like Columns 3 with odd ratios. ADR-0005 says "one center zone". Fix: a Layout-level normalized surround fraction (the tree tiles the Layout rectangle, Focus is one Zone numbered 1, drops in the surround go to the nearest Zone) with the one-line ADR-0003 and CONTEXT amendment the platform draft proposes; 20/60/20 is the fallback if the decision ticket refuses the amendment.

3. **US-109 and the reducer clear the Span "when the cursor's Display changes".** A 3-Display sweep that skims a seam loses a three-Zone Span with no way back but releasing Shift. Fix: suspend on the Span's DisplayKey, resume on return, a drop on another Display uses the Zone under the cursor, and the suspended Span is drawn dimmer.

4. **RestoreLedger "keeps the entry so Restore still works after a later re-Snap".** Snap, Restore, hand-move, Snap, Restore returns the frame from before the first Snap, not the hand-placed one; platform's round-1 attack 7 was not applied. Fix: a successful Restore removes the entry; the next Snap is a first Snap and captures the current frame.

5. **Permission `revoked(badge, onboarding visible, relaunch offered)`.** Offering relaunch while the grant is absent relaunches into an untrusted app and teaches the user the button is dead. Fix: split `revoked` (no relaunch button) from `needsRelaunch` (grant present again, tap still nil: "Quit and Reopen").

6. **"No probe while trusted" with no other idle signal.** Revocation while idle is discovered at the next mouse-down, so the badge US-004 promises can be an hour late. Fix: a 5 s heartbeat (one trivial AX read whose result feeds only the permission machine) while trusted, gated on the platform's open question 14; otherwise US-004 must say "at the next drag".

7. **Persistence "actor with a coalescing debounce so editor drags do not write per pixel".** US-031 applies on Save only, so there are no per-pixel writes; the debounce only opens a window in which a Save is lost on quit or crash, which US-082 does not cover. Fix: synchronous atomic write on Save, Assignment change and import; flush on quit; no debounce.

8. **Preferences "stored as one Codable value" versus US-120 (coerce field by field).** One blob fails as a whole on one unknown enum case; the coercion story needs a custom decoder the text never mentions. Fix: decode field by field with per-field defaults (or one key per field under the namespace); test that one unknown value loses only that value.

9. **US-088 ("Zones do nothing visible when the cursor is over the menu bar or Dock strip").** The panels cover the whole Display and stay; what happens is the highlight clears and a drop Restores. "Nothing visible" is untestable and the opposite of what the user sees. Fix: "the highlight clears, the Overlay stays, and a drop there Restores".

10. **DisplayKey "UUID string with vendor-model-serial fallback" and topology "falls back to the vendor-model-serial key if the UUID stays nil".** Two identical panels with serial 0 share one key and one Assignment that flips on every arrangement change. Fix: a fallback key is `unstable`, never persisted, accepts an in-session Assignment only, and the Layouts pane says why.

11. **"Mirror groups collapse to one DisplayKey" without saying which.** If the key differs between sessions the mirrored set's Assignment flips. Fix: the mirror master (the member that mirrors nothing); no Assignment persisted while mirroring is active.

12. **CI gate "no force unwraps" by grep.** `!` matches `!=`, negation and string literals; the gate is disabled in week one. Fix: gate on `try!`, `as!` and `fatalError(` with a per-line allow marker.

13. **Templates "Columns and Rows are chains of splits with equal ratios".** Equal ratios do not give equal columns: a right-leaning chain for three columns needs 1/3 then 1/2. As written the golden for Columns 3 is wrong or the test fails. Fix: the k-th split of an n-way chain uses ratio 1/(n-k+1); property test: every Columns and Rows Zone has equal extent within epsilon. (The power-user draft had the same wording; fixed in its revision.)

14. **US-055 ("shortcuts work without any extra permission").** Window shortcuts read and write frames through AX, so without the grant they are silent no-ops that satisfy the story while doing nothing. Fix: editor and Settings shortcuts need nothing; window shortcuts need Accessibility, never the tap; the General pane says which is missing.

15. **US-053 "warns on conflicts between Zones shortcuts" versus Shortcut dispatch "conflicts among Zones shortcuts are rejected in the recorder".** Story and decision disagree. Fix: reject duplicates within Zones (two actions on one chord is never valid); warn on system chords.

16. **ShortcutResolver "else Zone 1" versus US-114 and "cyclePrevious at the last Zone Number".** The resolver returns Zone 1 for both directions when nothing matches; two lines later Left starts at the last Zone. Fix: the resolver returns first for Right and last for Left; one table test.

17. **Reducer: "any state plus windowGone, wake, or topologyChanged emits hideOverlay and returns to idle".** A resolution change during an armed drag kills the session while the button is still down; the Overlay vanishes and the drop does nothing. Fix: `topologyChanged` while armed re-arms from the new snapshot (redraw, re-hit); only `windowGone` and `wake` abort.

18. **Editor stories (US-022 to US-031) have no ergonomics.** No divider snapping to halves, thirds, quarters and collinear dividers; no single-key split; no arrow nudge; no Zone Numbers drawn in the editor; no Display switcher, so on three Displays the editor is closed and reopened three times. The round-1 Steal list took none of it. Fix: lift US-077 to US-079, US-084 and US-085 from the power-user draft; the command list already supports them.

19. **US-030 opens the editor "on the Display under the cursor" but never says it draws at real scale over that Display.** A thumbnail editor makes the user guess what 8 points of Gap look like. Fix: full-Display window on the Display being edited, Zones drawn where the Overlay will draw them.

## Steal list

What the other drafts have that the power-user draft lacked; all are folded into the revised power-user draft.

From platform:
- The Overlay appears only after the move is confirmed (US-012) as a user-visible promise, not just a state-machine detail.
- Pixel-grid "what I saw is what I get" (US-049), with the Overlay model and the Snap target produced by one grid step.
- Zones' own work between mouse-up and the first write is the budget (US-053); per-app wall time is a manual matrix row.
- Shortcut changes during a Drag Session apply after it ends (US-070).
- Preferences decoded field by field so one bad value never resets the rest (US-104).
- "Exclude <App>" from the menu (US-090), adopted with a confirmation.
- Settings opens on the current Space and becomes key (US-097); template menu-bar icon (US-098).
- Revocation badge while idle via a 5 s heartbeat (US-120), gated on a spike.
- Copy Diagnostics shows the report before copying (US-132).
- `DisplayKey = uuid | unstable`; mirror master as the collapsed key; no Assignment persisted while mirroring.
- `EnhancedUIPolicy` as a value; `FrameWriteResult` with `timedOut` and `elementGone`; EUI pair skipped when absent or already off; eight round trips counted.
- InputTap coalesces `dragged` to the newest sample; down, up and flagsChanged are never dropped.
- Launch sequence with the status item created last.
- Candidate set held through `Pressed`, resolved by the first frame sample that moved.

From maintainer:
- Deterministic identifiers for built-in Layouts so Assignments can reference a Template without persisting it (US-122).
- Quit tears down the tap and panels and restores anything Zones changed in other apps (US-106).
- Opaque `WindowHandle` in Core; only the Windowing adapter knows it wraps an AX element.
- Import Merge or Replace; one document shape with both arrays optional, validated as a whole (US-074, US-077).
- Named Clock-driven constants for cooldowns instead of literals in prose.
- ZonesLayout owns a draft Layout plus a command list; selection, dirty and Display identity live in the app view model.
- HitTester tie rule: nearest by minimum edge distance, ties by lower Zone Number.
- Reducer invariant: the highlighted set always equals the set a mouse-up would snap to.
- Budget tests assert allocation counts and generous relative bounds on CI; absolute timings on the local checklist (US-123).
- Sibling-only merge in v1 per ADR-0003, with non-sibling rectangular merge as a spike that must deliver the algorithm and a golden table first.
