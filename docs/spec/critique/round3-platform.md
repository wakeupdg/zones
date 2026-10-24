# Round 3 critique — from the platform persona

Scope: attacks on the power-user and maintainer drafts as revised after round 2, from the lens of someone who has shipped Accessibility-API window tools on real Macs: TCC flows and revocation, AX write quirks, hung apps, CGWindowList without titles, Spaces and full-screen, display topology, sleep and wake, Electron and Java, 120 Hz drags, HIG for a menu-bar app, SwiftUI and AppKit integration. Judged against the locked ADRs, CONTEXT.md and the research Implications and Gotchas. Each attack quotes the story or decision, says why it fails on a real Mac, and gives a fix the synthesizer can lift.

## Attacks on power-user

1. **Permission machine, US-121: "`revoked` with trust reading true while the tap still fails becomes `needsRelaunch`".** Research (event-taps-tcc Gotchas) says the trust probe does not reflect revocation of a running process, so it reads true for the whole revoked period; the gate carries no information and `needsRelaunch` is reached by elapsed time alone, usually while the user is still inside System Settings looking for the switch. "Quit and Reopen" then relaunches into an untrusted app, the dead button US-121 wants to avoid. Fix: one `revoked` state with both "Open System Settings" and "Quit and Reopen" plus one sentence ("if you turned Zones back on and dragging still does nothing, quit and reopen"); tap recreation retried every 3 s so a re-grant that needs no relaunch heals itself; delete `needsRelaunch`; the manual checklist records what the probe actually reads after revocation.

2. **Enhanced UI safety: "a small recovery record (pid, bundle identifier, process launch date) is written only when a toggle actually happened and cleared after".** The in-memory set drains after every write, so "a toggle happened" is every Snap: a synchronous file write sits on the WindowActor between mouse-up and the first AX write on every Snap, against US-115. The record also lacks the prior value, so restoring "on" for an app whose Enhanced UI was off before the crash makes Chromium animate every later move (ax-window-moves: Enhanced UI drives animated moves). Fix: write once per (bundle identifier, pid, launch date) the first time that app is touched in a session, store the prior value, restore on launch only entries whose process matches all three and whose prior value was on, delete the file on clean quit.

3. **`pressed` and US-117: AX frame polling at about 60 Hz begins at mouse-down for every candidate.** A listen-only tap sees every mouse-down in every app; a 3 s text selection in Xcode or a scroll-thumb drag in a hung app becomes 180 serialized AX reads to that app on the WindowActor with no Overlay possible because no modifier is down. US-117 says "poll only the dragged window", but every click-drag in every app is "the dragged window". Fix: confirm movement by polling the CG window description of the candidate ids (a window-server query, no IPC to the app; cgwindowlist implication 4), started at the first `dragged` event; touch AX (element mapping, phase-2 facts, frame read) only on the transition into `armed`. A plain click or plain drag then costs the target app nothing, and a hung app cannot stall Zones until the user actually asks for a Snap.

4. **Input "a watchdog checks the tap every 2 s" beside the 5 s heartbeat and US-116 "exact idle timers enumerated".** Two idle timers at two periods where one suffices; the tap already delivers `tapDisabledByTimeout` as an event, so the watchdog is a backstop and 5 s is plenty. Fix: one 5 s health tick carrying the enabled check and, when the spike enables it, the heartbeat; US-116 lists exactly two timers: trust poll while not granted, health tick while granted.

5. **US-022 gates the Overlay over a full-screen Space on "the panel is visible there" only.** Visibility is half the question: whether macOS lets a managed window be dropped onto a Display whose active Space is full-screen is unverified, and drawing targets that cannot be hit is the Overlay lying (your US-033). Fix: gate on both; when the drop is impossible that Display leaves the arm snapshot, no Zones draw there, and a drop there is a logged no-op, not a Restore.

6. **Display geometry, US-048: "no Assignment is persisted while mirroring".** The master's key is a stable UUID (hardware mirroring leaves only the master in the active display list), so the rule protects nothing and throws away a Layout picked from the menu while mirroring. Fix: persist under the master key; delete the rule.

7. **Input: "window hotkeys are gated at dispatch", US-137.** Carbon consumes the chord system-wide whether the handler acts or not, so an untrusted user loses Control+Option+1..9 in every app for a silent no-op. Fix: register window hotkeys only in `granted` and unregister on leaving it; editor and Settings hotkeys stay registered always; registration diffing already handles the churn.

8. **Persistence: "Writes are synchronous and atomic ... flush on quit; no debounce."** Flush implies a buffer that synchronous denies; a maintainer will add the buffer to give "flush" a meaning and reopen the lost-Save window. Fix: delete "flush on quit"; the test is "after Save returns, the file on disk decodes to the saved document".

9. **WindowActor protocol `observe(destroyed)` names no thread.** AXObserver callbacks need a run loop source on a thread whose run loop runs (ax-window-moves Gotchas); an actor has no run loop; adding the source to the main run loop puts a hung app's observer on the UI. Unspecified means it never fires and Original Frames leak until `elementGone`. Fix: one dedicated observer thread with a running CFRunLoop forwards value-type notifications to the actor; the actor never owns a run loop source.

10. **Shortcut recorder "warns on a built-in list (Mission Control, Spaces arrows, screenshot chords, Command+digit, Command+arrow)".** System chords are user-remappable in Keyboard Settings and change per release, and a system chord registers successfully with Carbon while the system still wins, so neither the list nor the registration result reports the real conflict. Fix: rule-based warnings with no chord list: a modifier set that is Command-only or Command+Shift-only ("usually an app shortcut"), Control-only with an arrow or a digit ("usually Mission Control or Spaces"); everything else relies on the registration result and a manual row.

11. **US-150 "Settings and the editor ... become key immediately" from a Carbon hotkey.** An LSUIElement app must activate to become key; on macOS 14+ cooperative activation may refuse an activation not tied to a user interaction with the app, and a global hotkey is not one, so Settings opens behind the frontmost app. Fix: promise key status when opened from the menu and "where macOS allows" from the hotkey; the ticket uses the yielding activation path and the manual checklist verifies key status from the hotkey on 14 and 15.

12. **Editor "is a full-Display window on the Display being edited".** A window sized to the Display is managed by Stage Manager, cannot appear on a Display whose active Space is full-screen, and hides the very windows the user is laying out, so "what I see is what the Overlay will show" is judged against a blank backdrop. Fix: a standard resizable window defaulting to the Display's visible frame, Zones drawn at real scale over a translucent backdrop so the desktop stays visible; Stage Manager is a manual row.

13. **`DisplayKey`: "Nil UUID: retry on a Clock-driven delay, then fall back to `unstable`" with no count and no re-key.** If the retry succeeds after the Display settles, nothing re-emits a topology event, so consumers keep the `unstable` key for the session and the real Assignment never applies. Fix: three retries one second apart; a successful late read emits `topologyChanged` so Assignments and Overlay models re-key.

14. **US-003 "within a second of my flipping the toggle" with a 1 s trust poll.** Worst case is a full second plus the window update; the story sits on the edge of false, and Rectangle polls at 0.3 s. Fix: poll at 0.5 s while the onboarding window is visible (costs nothing once granted), 1 s otherwise.

15. **US-133 "a change mid-drag to redraw the Overlay rather than cancel my drag".** A resolution change mid-drag is macOS's own gesture to cancel: the window server reconfigures and many apps end the title-bar drag themselves; Zones cannot promise the drag survives. Fix: promise Zones' own behaviour (re-arm from the new snapshot, never abort from Zones) and record what macOS does on the manual row.

16. **`WriteResult` has no `noOp` case while the window service says "a target equal to the current frame within tolerance is a no-op that records nothing".** The planner must return something and callers will invent sentinels. Fix: `noOp` as a typed result (the maintainer's shape).

17. **Window registry: "Written only when absent, on `applied` or `clamped`" says nothing about which frame is the Original Frame on the mouse path.** The frame read just before the write is wherever the drag left the window, so Restore puts it back under the drop point instead of where it lived. Fix: on the mouse path the Original Frame is the mouse-down frame of the resolved window; on the keyboard path it is the read-back frame before the write; one scenario test each.

## Attacks on maintainer

1. **Permission state machine: "`revoked` moves to `needsRelaunch` only after three failed tap recreations over 10 s with the probe reading true".** The probe reads true throughout (event-taps-tcc Gotchas), so the condition is "10 s elapsed": `needsRelaunch` fires while the user is still finding the switch, and "Quit and Reopen" relaunches into an untrusted app. Fix: delete `needsRelaunch`; `revoked` offers both buttons with one explanatory sentence, retries tap creation every 3 s, and the manual checklist records the probe's real post-revocation value.

2. **WindowActor and resilience: the recovery file is "written ... only on the transition from empty to non-empty".** The set is drained by the defer after every write, so every Snap is that transition and the write lands between mouse-up and the first AX write; the file also carries no prior value, so restoring "on" at launch for an app whose Enhanced UI was off breaks Chromium moves afterwards. Fix: write once per (bundle identifier, pid, launch date) at first touch per session, store the prior value, restore only matching entries whose prior value was on, delete on clean quit.

3. **Reducer: "Candidates that fail ExclusionPolicy never enter pending" plus frame polling in `pending`.** Subrole, settable flags and full-screen are AX facts, so every mouse-down in every app issues several AX reads to that app plus 60 Hz frame polling until mouse-up, all serialized on one actor; one hung app the user merely clicks in stalls everything for 250 ms per call, and no Overlay was ever possible. Fix: phase 1 from CG facts only at mouse-down; movement confirmed by polling the CG window description of the candidate ids starting at the first `dragged` event; AX (element mapping, phase-2 facts, frame read) only on the transition into `armed`.

4. **WindowActor: "A `timedOut` result marks that pid unresponsive for a Clock-driven cooldown (5 s) ... One retry after the cooldown."** This inverts ax-window-moves implication 5 (retry once, then mark unresponsive): a 300 ms hiccup while Chrome loads a page costs the user 5 s of no Overlay for that app. Fix: one immediate retry of the same call, then the cooldown; the retry count is asserted in the fake test.

5. **CycleResolver fixture "Span covering 1 and 2 cycles Right to 2" versus the power-user's "after the highest member" (3), and the base depends on Layout ratios.** On Priority Grid a Span of 1 and 2 has its maximum intersection in Zone 2, so Right goes to 3; on equal Columns the members tie, the lower wins, and Right goes to 2. Same gesture, different result per Layout, and the two drafts disagree. Fix: store `LastSnap { zones, frame }` per handle on `applied` or `clamped` and consult it while the read-back frame still matches within 1 pt (no invalidation signal, no timer); Right from its highest member, Left from its lowest; maximum intersection is the fallback after a hand move.

6. **Topology: "A Display whose UUID reads nil is retried after the next event."** A single reconfiguration produces no next event, so the Display stays keyless for the session. Fix: Clock-driven retries, three at 1 s, then `unstable`; a late success emits TopologyChanged so consumers re-key.

7. **ExclusionPolicy reason `systemDialog` is undefined without titles or owner names (ADR-0020).** Finder is a system bundle and must snap; a save sheet is already `sheetOrPopover`; what remains is subrole or a fixed set of system agents. Fix: define it as owning bundle in {Dock, WindowManager, Notification Center, Control Center, loginwindow, UserNotificationCenter} or subrole in {systemDialog, systemFloatingWindow}; one table row each; anything else folds into `nonStandardSubrole`.

8. **Layout math: "Merge in v1: siblings, plus two adjacent leaves within one same-axis chain of splits (deterministic re-chaining)".** ADR-0003 defines merge as collapsing a node into one leaf; re-chaining rewrites a subtree and is filed under no Challenge. The arithmetic is unstated: in A | (B | C), merging A and B needs ratio r1 + (1 - r1) * r2 and a reparented C, which undo must invert exactly. Fix: either file it as a Challenge to ADR-0003 with the formula and a golden table, or keep v1 sibling-only and send the chain case to the C3 spike.

9. **Layout math: "Columns and Rows are chains of splits with equal ratios".** Still wrong after the round-2 attack: equal ratios give 1/2, 1/4, 1/4 for three columns. Fix: the k-th split of n uses ratio 1/(n - k + 1); property test asserts equal extents within epsilon.

10. **GeometryResolver: "round every edge to the backing grid carrying the remainder to the last Zone per axis".** The last Zone is wider than its siblings, "last" is traversal order so a mirrored Layout rounds differently, and the property was weakened to "at least Gap" to hide it. Fix: snap each shared edge coordinate once; neighbours share the rounded edge; tiling and exact-Gap tests run on unrounded output; a grid test asserts every edge on the grid and separation within half a backing pixel.

11. **Snap engine: Restore "clamped onto the nearest Display's visible frame first".** Nearest to a stale frame can be a Display the user is not looking at. Fix: clamp onto the Display the window currently occupies (maximum intersection of its read-back frame).

12. **US-125 "Settings and the editor ... become key" from a hotkey.** Same macOS 14+ cooperative-activation hazard as power-user attack 11; a global hotkey is not a user interaction with Zones. Fix: promise key status from the menu, "where macOS allows" from the hotkey, and a manual row for both releases.

13. **`Assignment` carries "last frame and visible frame" but no scale.** Editing a detached 2x Display at its last size resolves the backing grid and the 120x80 point warning wrongly. Fix: add scale (and lastSeen for ordering the Layouts pane).

14. **US-121 enumerates "the trust poll while not granted and the tap health check" while the permission machine adds a spike-gated heartbeat.** Story and decision disagree about the idle timers. Fix: the story names the heartbeat as gated, or the heartbeat shares the health tick so the count stays at two.

15. **WindowSystem "observe destroyed for a handle" names no thread.** Same run-loop hazard as power-user attack 9; unspecified means it never fires. Fix: a dedicated observer thread with a running CFRunLoop forwarding value-type notifications.

16. **US-003 "within a second" with a 1 s probe.** Same edge as power-user attack 14. Fix: 0.5 s while the onboarding window is visible.

17. **US-035 "including over a full-screen app on another Display where macOS allows it" covers drawing, not dropping.** If the drop is impossible the Zones drawn there cannot be hit and `hitTest` would report `none`, which Restores. Fix: a Display where the drop is impossible leaves the arm snapshot; a drop there is a logged no-op.

18. **OriginalFrameLedger "records the Original Frame on the first applied or clamped Snap" without saying which frame.** On the mouse path the pre-write frame is where the drag left the window. Fix: mouse path captures the mouse-down frame of the resolved window; keyboard path captures the read-back frame before the write.

## Steal list

What the other drafts have that the platform draft lacked; all are folded into the round-3 revision.

From power-user:
- An unstable DisplayKey accepts an in-session Assignment held in memory, labelled "not saved" in the Layouts pane (US-154).
- A suspended Span stays drawn on its Display in a dimmer style, an outline under Reduce Transparency (US-155).
- Restore clamps onto the Display the window is on, not the nearest to a stale frame (US-134).
- Appearance holds the default Margin and Gap used by Templates and new Layouts; a custom Layout's own values override in the editor (US-157).
- Focus is one Zone, Zone Number 1, and a drop anywhere on that Display lands in it (US-159), stated as a story.
- Export of one Layout as well as all, as the same document shape (US-097).
- The listen-only tap as an acceptance criterion: Zones never consumes the modifier (US-105).
- A shortcut re-recorded during a Drag Session is applied after the session ends (US-148).
- `RecorderState` as a typed shape for the recorder.
- One `grid` step that snaps shared edges, used by both the Overlay model and the Snap target (US-147).

From maintainer:
- `noOp` as a typed `FrameWriteResult` case.
- Signing identity in About and in the diagnostics report (US-072), so a lost grant after an ad-hoc update explains itself.
- One Assignment map with dormancy derived at read time from the current snapshot.
- Window hotkeys registered only while granted and unregistered on leaving it (US-138).
- Abort the write sequence at the first `timedOut`; only the Enhanced UI restore follows.
- Candidate set capped at two by z-order; more fail closed before any sampling.
- The checkable "Exclude <App Name>" menu item (US-126); the same click undoes it, no alert.
- `spaceChanged` as a reducer event that re-asserts the Overlay.
- The 10,000-event reducer bound stated as an order-of-magnitude number (2 s).
- Heartbeat bounded to one in flight and skipped during a Drag Session.
