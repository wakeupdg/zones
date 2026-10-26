# Round 2 critique — platform persona

Lens: will it be correct on a real Mac. TCC and revocation, AX write quirks, CGWindowList without titles, Spaces and full-screen, display topology, sleep and wake, Electron and Java, 120 Hz drags, HIG for a menu-bar app, and where each piece of AppKit or CoreGraphics may legally run. Each attack names the story or section, says what breaks, and proposes a fix. Round-1 attacks that the target draft did not act on are repeated briefly with a pointer.

## Attacks on power-user

1. **US-128 and Window service, "pids whose Enhanced UI Zones turned off are written to a small recovery file before the write ... on launch any listed pid still running has it restored".** Wrong on two counts. A disk write sits inside every Snap between mouse-up and the first AX write, on the path the same draft budgets at 50 ms. And pids are recycled after a reboot or an app relaunch, so "still running" is satisfied by an unrelated process and Zones flips Enhanced UI on in an app it never touched, which is exactly the VoiceOver regression the story wants to avoid. Fix: an in-memory set of pids drained by the defer on every write, on Quit and on entering `revoked`; the crash-mid-write case is a v2 hardening note keyed on bundle identifier plus process start time, not a v1 story.

2. **US-017, "the Overlay to appear within one frame of pressing the modifier".** Impossible as written when the modifier is pressed before movement: ADR-0006 confirms a move by polling the frame, so a Shift-click must show nothing (the draft's own US-125) and the Overlay can only follow the first frame sample that proves movement. At about 60 Hz polling that is up to two display refreshes on a 120 Hz Display. Fix: "within one display refresh of the first frame sample that confirms movement while the modifier is down, and within one refresh of a modifier press once already moving"; the second clause is the one that is testable as a reducer effect.

3. **US-035 and the Drag Session section, "crossing Displays clears the set".** On a three-Display desk a fast sweep skims the seam for one event; at 120 Hz one pixel over the edge and back throws away a three-Zone Span with no cue. Fix: the Span is scoped to one Display and *suspended* when the cursor leaves it; a drop on the other Display uses the Zone under the cursor there; returning resumes the set. Reducer test: leave-and-return preserves the set.

4. **Window registry, `WindowKey (pid + AX element hash)` in ZonesCore.** A hash is not an identity. Two windows of one app can collide and the failure is silent: Restore writes one window's Original Frame onto the other. It also leaks an AX concept into Core against ADR-0002. Fix: Core holds an opaque `WindowHandle` (Hashable, Sendable); the production box in Windowing wraps the element, equality is CFEqual, hashing is CFHash, and it is the single documented unchecked-Sendable type.

5. **Window registry, `placement` "cleared when an observer reports a move or resize that Zones did not issue".** Untestable and racy on real apps: `kAXWindowMovedNotification` is documented end-of-gesture only, Zones' own write fires the same notification, Chromium fires resized several times per write, and correlating under a 250 ms timeout mis-fires both ways. Fix: no observer. Each Snap records the read-back frame with its target Zone set; at cycle time, if the current frame equals the recorded frame within one point the cycle starts from the record (so a clamped Calculator at Zone 3 still cycles to 4), otherwise from the Zone with the largest intersection. Pure comparison, no notifications.

6. **US-022 and US-104, Overlay over a full-screen app's Space and "already visible on Display 2".** Research marks panel visibility over full-screen and Split View Spaces [Unverified], and macOS often refuses to drop a managed window into a full-screen Space at all (the window bounces back). The story promises what the OS may not allow. Fix: "where macOS allows the drop"; gate on spike 6; expected result lives on the manual checklist, not in a story a ticket can close.

7. **US-041, mixed scale factors, and Layout model "rounded to whole points, with the last Zone on each axis absorbing rounding".** AX frames are in points on every Display, so scale never changes the size; what changes is the legal grid (half points at 2x). Rounding to whole points makes the Overlay and the Snap disagree by up to a point on Retina and "last Zone absorbs" makes a Zone's width depend on traversal order. Fix: resolve on the backing grid (one divided by scale) with the remainder carried per axis, round once, and run the tiling property test at scales 1, 2 and 3.

8. **US-061, "every default shortcut to include Control or Option".** Still contradicts the draft's own ShortcutStore ("requires Control or Command") after round 1. Research: Option-only is the broken case on macOS 15; "Control or Option" permits it. Fix: "Command or Control", one rule, one rejection test.

9. **US-027, "a resize-by-edge drag (origin fixed, size changing)".** A resize from the left or top edge changes the origin *and* the size, so the stated rule classifies it as a move and arms the Overlay. Fix: any size change in the first sample ends the session; `moving` requires origin changed with size equal within tolerance.

10. **US-117 (no polling at all while idle) versus US-120 (badge before a failed drag when permission is lost).** Research says the trust probe does not report revocation of a running process, so with zero timers the only revocation signals are the next AX call or a tap event. The two stories cannot both be true. Fix: state it honestly: the badge follows the first failed AX call or tap signal; a 5 s heartbeat read is enabled only if spike 14 shows the API-disabled code arrives promptly after revocation.

11. **Overlay section, "Zone layers are rebuilt from `resolve` on each arm" versus "layer rebuild for every Display under 4 ms".** Creating CALayers for three Displays times nine Zones on every arm allocates on the hot path and resets `contentsScale`. Fix: panels and layers persist; an arm sets layer frames, colors and labels inside one CATransaction with actions disabled; layers are rebuilt only on TopologyChanged or a Layout change.

12. **Persistence, "Preferences in UserDefaults as one Codable value" versus US-143 and US-120 coercion.** A single Codable blob fails to decode as a whole when one enum case is unknown, so one hand-edited modifier wipes every preference, which is the exact loss US-143 forbids. Fix: decode field by field with a per-field default (or one UserDefaults key per field); the coercion table test then has something to test.

13. **Input, "three failures in a minute set `tapState = dead`".** `tapDisabledByTimeout` is normal under load (Spotlight indexing, Time Machine) even for a listen-only tap on its own thread. Three per minute leaves busy Macs with a dead tap and a badge. Fix: a rate limiter of about five re-enables per minute with backoff; after the limit, `dead` with an automatic retry every 30 s and the badge; Loop's shape.

14. **Drag Session, `pressed` "ambiguity or an excluded/unmovable/full-screen/own window yields idle".** Deciding unmovable, full-screen and subrole needs AX reads, and `pressed` is entered on *every* left mouse-down on the system, including clicks that never move. Against a hung app that is a 250 ms WindowActor stall per click. Fix: two-phase policy: at mouse-down only CG facts (own pid, layer, bundle Exclusion); AX facts (role, subrole, settable, full-screen) on the first frame sample, which already costs one AX read.

15. **Shortcut dispatch has no rule for a window shortcut fired during a Drag Session.** Carbon hotkeys fire while the mouse button is down; a Control+Option+3 mid-drag issues an AX write while the WindowServer is moving the same window, and Chromium ends up in neither place. Fix: window commands are ignored (logged) while the Drag Session is not idle; editor and Settings commands still run.

16. **Permission section, "built on open from the Display whose menu bar was clicked".** With "Displays have separate Spaces" off there is one menu bar, so "whose menu bar I clicked" is undefined for the other Displays, and ADR-0019 says "the display under the cursor". Fix: use the ADR wording; the cursor is on the clicked menu bar when separate Spaces is on, so both cases are covered by one rule.

## Attacks on maintainer

1. **Layout math and Challenge 1, Focus as "a three-column split 20/60/20 whose center is Zone Number 2".** Contradicts ADR-0005 (one center Zone at 60 percent) and defeats the Template: Control+Option+1 sends a window to a 20 percent sliver, the Overlay shows three targets where every FancyZones user expects one, and a near-miss drop lands in the surround. Fix: a Layout-level normalized surround fraction applied before Margin so the tree tiles the Layout rectangle; Focus is one Zone numbered 1; a drop in the surround resolves to `nearest`. Needs a one-line amendment to ADR-0003 and CONTEXT ("tiles the Layout rectangle"); if the decision ticket rejects it, option (a) must at least number the center as Zone 1.

2. **Drag Session states still include `cooldown(until)`.** Round-1 attack M5 was accepted in the Steal list but the state list did not change. A pid cooldown as a session state blocks drags of every app. Fix: delete the state; ExclusionPolicy consults per-pid health and returns `skip(unresponsive)`.

3. **US-109, Span "cleared when the cursor crosses to another Display".** Same seam-skim failure as power-user attack 3. Fix: suspend and resume; drop on the other Display uses the Zone under the cursor there.

4. **Reducer, "any state plus windowGone, wake, or topologyChanged emits hideOverlay and returns to idle".** A Dock resize, a Display waking from its own sleep, or a resolution change mid-drag kills a live drag while the button is still down; the user sees the Overlay vanish and the drop do nothing. `wake` to idle is right (mouse state is unknown); `topologyChanged` is not. Fix: `topologyChanged` while `armed` re-arms from the new snapshot (Overlay and Snap share one geometry); while `pending` or `moving` it refreshes the snapshot and keeps state.

5. **Reducer, "pending to moving when a frameSample differs from downFrame by more than a threshold; pending to idle ... when a frameSample shows only a size change".** A resize from the left or top edge changes origin and size together, satisfies the first clause and is not "only a size change", so it arms the Overlay. Fix: any size change ends the session; `moving` requires origin changed with size equal within tolerance.

6. **ShortcutResolver, "neighbor ... from the Zone whose rect best matches the current frame, else Zone 1" versus US-114 (Left starts at the last Zone).** Two rules for one case inside one section. Fix: one sentence: no match means Right starts at 1 and Left at the last Zone. Also adopt the read-back record from power-user attack 5 so a clamped window cycles from the Zone Zones sent it to.

7. **Documents, "Persistence is an actor with a coalescing debounce so editor drags do not write per pixel" versus US-031 (Save is the only write).** Round-1 attack M12 unapplied. Fix: the editor writes on Save; menu Assignment changes write immediately and synchronously (one small file); no debounce anywhere, nothing to flush on quit.

8. **Challenge 4, EnhancedUIPolicy `auto` "would toggle only for known Chromium and Electron bundle identifiers".** Round-1 attack M14 unapplied; a bundle list is unmaintainable. Fix: `auto` is defined by a measurable signal: read the app element's Enhanced UI attribute; toggle only when it is on, skip the pair when it is absent or off. No list, and the read is one message.

9. **WindowSystem, "observe destroyed, moved, resized for a handle" on the WindowActor.** An AXObserver needs its run loop source on a thread whose run loop runs; a Swift actor has no run loop, so the callbacks never fire or fire on a thread the actor does not own. Fix: observers live on one dedicated thread with a running CFRunLoop (or the main run loop) and forward value-type notifications to the actor; the spec must say which, or the ticket author will discover it in week two.

10. **US-088, "do nothing visible when the cursor is over the menu bar or Dock strip" versus Challenge 3 (that strip is the Restore target).** Round-1 attack M10 unapplied. A drop there Restores with no cue. Fix: the Overlay stays up, the highlight clears and every fill dims; no text on the Overlay (text layout on the hot path and against the platform draft's Out of Scope).

11. **US-064, automatically skip "windows that refuse resizing" versus SnapPlan "whether size is settable".** Round-1 attack M3 unapplied in the story. Fix: skip only when position is not settable; size-locked windows get a position-only plan, top-left aligned.

12. **DisplaySnapshot has no backing scale.** GeometryResolver cannot round to the legal grid (half points at 2x) without it, and a window crossing a 2x to 1x seam lands a half point off. Fix: add `scale` to the snapshot and run the tiling and rounding property tests at scales 1, 2 and 3.

13. **InputSource, "AsyncStream of InputEvent".** An unbounded stream at 120 Hz buffers every mouseDragged when the consumer stalls for one slow frame; the highlight then replays stale positions. Fix: bounded with newest-wins for dragged events; down, up and flagsChanged are never dropped; stated as a protocol contract with a fake that can inject a stall.

14. **Shortcut dispatch has no rule for a hotkey fired while a Drag Session is active.** Same as power-user attack 15. Fix: window commands ignored while the reducer is not idle; one log line.

15. **Topology, "Mirror groups collapse to one DisplayKey".** Which one? If it is whichever member enumerates first, the Assignment flips on every mirror toggle. Fix: the mirror master (the member that mirrors nothing); no Assignment is persisted while mirroring is active; unmirror restores each member's own Assignment.

16. **Reducer, "idle to pending on mouseDown with a candidate that passes ExclusionPolicy".** The policy's subrole, settable and full-screen facts are AX reads on every left click system-wide. Fix: two-phase policy as in power-user attack 14: CG facts at mouse-down, AX facts at the first frame sample.

17. **Preferences, "Stored as one Codable value in UserDefaults" versus "coerced field by field".** A single Codable value cannot be coerced field by field; the decoder fails as a whole on one unknown enum case. Fix: per-field decoding with defaults, or one key per field.

18. **US-055, "shortcuts to work without any extra permission".** Round-1 attack M8 unapplied in the story; only the editor and Settings shortcuts work without Accessibility. Fix: split the story as the shortcut section already does.

19. **Launch sequence, "badge only when launched at login", detection unnamed.** The only reliable signal is the launched-as-login-item flag on the open-application Apple event, readable only inside the did-finish-launching callback; checked anywhere else it is always absent. Fix: name the signal and its window in Implementation Decisions.

## Steal list

From power-user (adopted into the platform draft):
- The FancyZones Span release rule (set kept while the cursor stays inside the Span rectangle; a Zone outside replaces it) with the invariant that the highlighted set equals what a mouse-up snaps (US-038, US-052 revised).
- One DisplaySnapshot per arm feeds Overlay and Snap; TopologyChanged while armed re-arms (US-046 revised).
- Layouts pane lists disconnected Displays with Copy Assignment to an attached Display and Forget (US-141 replaces US-083).
- Snap onto a Display with a different scale factor sizes correctly on arrival (US-137).
- Overlay fills translucent above the dragged window; highlight distinct from idle Zones at low opacity (US-138).
- Editor Assign in one click; Save and Close shortcuts (US-139).
- Settings and editor open on the Display under the cursor (US-140).
- "Reset and re-onboard" action in General (US-143).
- Template names carry Zone counts in the menu ("Columns 3"); General shows the two modifiers as key caps; Zone Number labels legible at any fill opacity (US-145, US-146, US-147).
- Numeric budgets in US-018 instead of "without stutter".
- Inline Layout picker instead of a submenu.

From maintainer (adopted):
- Built-in Layouts with deterministic identifiers generated at load, never persisted, referenced from assignments.json (US-144).
- InputSource filters right and middle buttons at the source; `wake` as a reducer event that ends any Drag Session.
- In-memory Enhanced UI set drained on defer, Quit and `revoked`; no recovery file.
- No periodic sweep; eviction on destroyed, elementGone and process termination.
- Protocol seams with fakes for HotkeyService and LoginItemService; toggle derivation and registration diff as table tests.
- Budget tests as allocation counts and generous relative bounds on CI; absolute timings on the local checklist.
- Manual contract tests that run each production adapter against the real OS on demand.
- Vertical ticket rule (protocol, fake, logic, tests, adapter) and maintainer stories kept as acceptance criteria.
- Logger facade with subsystem and category; test sink is an array.
- Clock-driven retry for a nil Display UUID with the vendor-model-serial fallback.
