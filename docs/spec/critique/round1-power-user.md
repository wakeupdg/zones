# Round 1 critique — power-user persona

Attacks target the platform draft and the maintainer draft by story id or section name. Each attack: what is attacked, why it is wrong, and a concrete fix. The Steal list names what those drafts got right that the power-user draft lacked; every item on it has been folded into the power-user draft as US-121 onward or as a revision to an existing story.

## Attacks on platform

P1. US-038 and US-052 (Span frozen when the Span Modifier is released). Wrong: ADR-0007 makes the Zone under the cursor the target; a frozen Span drops the window where the cursor is not, and the draft's own state machine never mentions Span release. It also removes any recovery from a mis-sweep short of releasing the Activation Modifier. Fix: FancyZones rule. On Span release the set is kept while the cursor stays inside the Span's bounding rectangle; a Zone hit outside that rectangle replaces the set with that Zone. "Let go and drop" still works and the cursor stays truth.

P2. Drag Session state machine, `Pressed --dragged & frame != frame0--> Moving`. A size change counts as a move, so a Shift-drag on a window edge arms the Overlay and Snaps on release, hijacking resize in drawing apps. Contradicts ADR-0006 ("a real window move"). Fix: origin changed with size unchanged -> Moving; size changed -> Idle for this session.

P3. US-046 versus US-049. Contradiction: the visible frame is "read fresh at drop time" yet the Snap must "honour the Zone drawn on the Overlay exactly". If the Dock appears mid-session, the drop differs from the picture. Fix: one DisplaySnapshot taken at arm feeds both the Overlay model and the Snap; a TopologyChanged while armed re-arms (rebuilds the Overlay from the new snapshot). WYSIWYG then holds by construction and is a scenario test.

P4. Window command path, cycle by "best-match". A window sent to Zone 3 whose app clamped its size (Calculator), or a Spanned window, best-matches a different Zone; Control+Option+Right after Control+Option+3 lands in 2 or stays put. Fix: a placement record (zone or span) is consulted first and cleared when an observer reports a move or resize Zones did not issue; best-match is the fallback only. Scenario: send to 3, app clamps, cycle right -> 4.

P5. PermissionMonitor polls `AXIsProcessTrusted` every 5 s while granted. The draft's own Challenge 1 states that the poll cannot see revocation of a running process, so this is a wake-up carrying no information and breaks an idle-zero-timers budget. Fix: no poll while granted; runtime signals only (nil tap, tapLost, apiDisabled); poll only in NotGranted and Suspect.

P6. OriginalFrameRegistry "1 Hz sweep while non-empty". If the sweep reads AX per handle, 20 snapped windows cost 20 serialized AX calls per second on the WindowActor; one hung app at 250 ms each stalls drag polling for 5 s per sweep. Fix: sweep by pid liveness only (process table, no AX); evict on the destroyed notification and on invalidUIElement from a real call; if any AX probe is kept, at most one per tick.

P7. US-090, "Exclude <App>" resolving "the bundle identifier of the window under the cursor". When the menu is open the cursor is on the menu bar; the story also says "frontmost app". Fix: frontmost app's bundle id, item titled "Exclude <App Name>", with a one-line confirmation because the effect is immediate and global.

P8. US-083 (Display identifier changed; offer "use the Layout from the Display that disappeared"). Zones cannot distinguish a changed UUID from a new Display; any offer is a guess, and ADR-0012 keys by UUID only. Fix: the Layouts pane lists disconnected Displays (name, resolution, Assignment) with "Copy Assignment to <attached Display>" and "Forget". User-driven, no heuristic, and it also covers moving between desks.

P9. US-110, "refuse an edit that would leave ... more than nine numbered Zones (warning only above nine, not refusal)". Self-contradictory; Grid 3x3 is exactly nine and Columns 5 x Rows 2 is ten. Fix: never refuse on count; the editor badges "Zones 10+ have no chord" and Overlay labels still render.

P10. US-103 (import collision asks replace or keep both per Layout). One modal per collision; re-importing your own export is N prompts. Fix: one choice for the whole import, Merge (keep existing, rename incoming) or Replace (backup aside first); zero per-item prompts. The maintainer draft's US-074 already has this shape.

P11. US-018, "without stutter or lag", is untestable as written. Fix: numeric budgets in the story: highlight update per dragged event under 2 ms on the main actor, arm-to-first-frame on the next display refresh, and the draft's own headless budget (10,000 reducer events under 50 ms) cited as the guard.

P12. US-079 (Stage Manager: "never touch recent-apps thumbnails") versus Out of Scope ("no special handling of Stage Manager"). A story promises what scope disclaims and nothing can verify it headless. Fix: drop the story; keep the manual checklist line and open question 11.

P13. Menu-bar shell, Layout picker as a submenu. ADR-0019 says the menu shows a layout picker; a submenu adds a hover target to a daily action on three Displays. Fix: inline radio list, Templates grouped then custom Layouts, active one checked, Display name as a disabled header above.

P14. US-070 (re-record a shortcut during a Drag Session). Recording needs a key-down in the Settings recorder while the mouse button is held on another window's title bar; unreachable. Fix: delete it; registration diffing on preference change (maintainer draft) covers the real race.

P15. Diagnostics, "last 10 SnapRecords". Ten Snaps is a minute of a 3-Display session; the failing one is gone before About opens. Fix: a 200-event ring (maintainer draft) exportable as one text block with no titles.

P16. US-022, "I want Zones drawn only inside the usable area". "Zones" is the app name; the plural of the glossary term reads as the app. The synthesizer will copy it. Fix: "I want the Zones of the Layout drawn only inside the usable area".

## Attacks on maintainer

M1. Layout math, Focus as "a three-column split 20/60/20 whose center is Zone Number 2" (Challenge 1, option a). Contradicts ADR-0005 (one center Zone at 60 percent) and defeats ADR-0004's purpose: Control+Option+1 sends a window to a 20 percent sliver and the Overlay shows three targets where FancyZones users expect one. Fix: keep the split tree (ADR-0003) and mark the surround leaves inert: the tiling invariant holds, inert leaves never highlight, never number, render unfilled, and a drop on them resolves to the nearest Zone (the center). Numbering skips inert leaves, a one-line filter, not a new concept. If a decision ticket rejects inert leaves, option (a) must at least number the center as Zone 1.

M2. HitTester returns none for Margin and Gap, plus Challenge 3 ("ship non-zero Margin and Gap so the Restore path exists"). This turns every Zone boundary into a Restore trap: a sweep released one point into an 8-point Gap teleports the window; a Span sweep across a Gap emits none mid-sweep. Fix: Gap and Margin resolve to the nearest Zone; "outside every zone" (ADR-0009) means outside the visible frame. Two of three drafts agree; the ADR owner should confirm the wording.

M3. US-064, automatically skip "windows that refuse resizing". Research (ax-window-moves, implication 2) says position-only; fixed-size windows (Calculator, utility panels) are exactly what a power user parks at a Zone's top-left. Fix: skip only when position is not settable; size-locked windows get position-only placement. Platform US-087 agrees; this is C1 in the power-user draft.

M4. Reducer, "accumulating the swept set while the Span Modifier is down and replacing it otherwise". Releasing Control and then moving one pixel before mouse-up (hand jitter) collapses the Span to one Zone. Fix: the FancyZones rule from P1: keep the set after release while the cursor stays inside the Span rectangle; a Zone outside it replaces the set.

M5. Reducer state `cooldown(until)` inside the Drag Session. An unresponsive-app cooldown belongs to the pid; as a session state it blocks drags of every app for the cooldown. Fix: remove the state; ExclusionPolicy consults per-pid health and returns skip(unresponsive); the reducer stays idle, pending, moving, armed.

M6. RestoreLedger "keeps the entry so Restore still works after a later re-Snap". After Restore the user hand-moves the window, Snaps again, Restores: it returns to the pre-first-Snap frame, not where they left it. ADR-0009 does say "forgets it when the window closes", so this is a challenge, not a drafting error; the draft should at least state the surprise. Proposed (C5 in the power-user draft): Restore, and an external move or resize observed between Snaps, clear the record so the next Snap re-captures.

M7. ShortcutResolver, cycle "from the Zone whose rect best matches the current frame". Same failure as P4: clamped or Spanned windows cycle from the wrong Zone. Fix: placement record first, best-match fallback.

M8. US-055, "shortcuts to work without any extra permission, so that keyboard control never depends on the event tap". Half true and misleading: hotkeys fire without permission, but moving a window needs Accessibility; only editor and Settings shortcuts work when the grant is missing. Fix: split into two stories (platform US-064 wording) and gate window commands at dispatch by permission state.

M9. US-053 "warns on conflicts between Zones shortcuts" versus Implementation "Conflicts among Zones shortcuts are rejected in the recorder". A duplicate chord means one action silently never fires. Fix: reject duplicates within Zones; warn, not block, on the built-in list of system chords.

M10. US-088, "do nothing visible when the cursor is over the menu bar or Dock strip", versus Challenge 3 (that strip is the Restore target). A drop there Restores, a large effect with no cue. Fix: the Overlay stays up, the highlight clears, Zone fills dim, and a short label on the Display under the cursor reads "Release to restore" for the first few times. It is the only mouse path to Restore and must be discoverable.

M11. Editor stories US-022 to US-031. No keyboard split, no divider snapping to halves, thirds and quarters, no arrow nudge, no Zone Number preview, no Display switcher: a form with a tree. The brief's editor is faster than fiddling with numbers. Fix: adopt US-077, US-078, US-079, US-084, US-085 and US-088 from the power-user draft; the command-list model already supports them.

M12. Persistence "actor with a coalescing debounce so editor drags do not write per pixel" versus US-031 "edits apply only when I press Save". If Save is the only write there is nothing to debounce; two mental models for one path. Fix: the editor writes on Save only; the debounce applies to menu Assignment changes, which are immediate; say so.

M13. US-074, Replace mode. One click replaces every Layout and Assignment; "swaps both documents in one transaction" is atomic but unrecoverable. Fix: Replace writes a timestamped backup of both documents first and names it in the confirmation; Merge is the default button.

M14. EnhancedUIPolicy `auto`, "toggle only for known Chromium and Electron bundle identifiers". A bundle list is unmaintainable (every Electron app has its own id) and the platform draft explicitly rejects bundle lists. Fix: v1 is `always` (ADR-0022) with the enum kept; `auto` is defined later by a measurable signal or dropped. Never ship a list.

M15. US-025, "minimum fraction". Right for the validator, but the symptom users see is points: 1/12 of a 13-inch Display is a 110-point sliver. Fix: validator enforces the fraction; the editor additionally warns when the resolved Zone on the current Display is under about 120x80 points. The power-user draft adopts the fraction and keeps the point warning.

M16. Permission state machine, `trusted` jumping straight to `revoked` on "any AX call returning the API-disabled code". One transient error during a Space switch would re-onboard a healthy app and offer a relaunch. Fix: the platform draft's Suspect state: recreate the tap and make one trivial AX read; return to trusted on success, revoked after 3 s otherwise.

## Steal list

From the platform draft (now in the power-user draft as noted):
- US-005 Quit and Reopen when a re-grant needs a relaunch, with the Suspect and NeedsRelaunch states -> US-121, permission state machine, C6.
- US-008 badge and a Grant Accessibility menu item only at login without the grant -> US-122.
- US-025, US-026 background-window drags work; a click with no movement records nothing -> US-125, US-126.
- US-033 right and middle buttons ignored mid-drag -> US-127.
- US-034 both modifiers held from the start begin the Span at the first Zone entered -> US-129.
- US-042, US-116 Enhanced UI restored on every path and after a crash via a recovery file -> US-128.
- US-050, US-051 Span rectangle includes Gaps; re-sweeping a member never removes it -> US-130.
- US-059 Restore clamps an off-Display Original Frame onto the window's Display -> US-134.
- US-069 keyboard Snap captures the Original Frame -> US-135.
- US-071 a cleared shortcut stays unbound -> US-136.
- US-064 editor and Settings shortcuts work without the grant -> US-137.
- US-075, US-081, US-082 resolution change recompute, nil UUID retry, identical Displays kept distinct -> US-131, US-132, US-133.
- US-031, US-115 sleep and wake re-validation -> US-124.
- US-100, US-102 import validation that never partially applies; migration with backup -> US-140, US-141.
- US-111 edit a disconnected Display's Layout at its last known size -> US-138.
- Headless performance budget tests (hit test, allocation-free resolve, reducer throughput) -> Testing Decisions.
- Challenge 1 refinement of ADR-0021 -> C6.

From the maintainer draft:
- US-009 menu opens instantly while an app is hung -> US-123.
- US-031 Save is the only moment the live Layout changes; Cancel discards -> US-139.
- US-081, US-082, US-089 future-version file left alone, atomic writes, preferences schema version -> US-141, US-142, US-143.
- US-083, US-084 Copy Diagnostics with no titles -> US-144, Diagnostics section.
- ExclusionPolicy skip reasons logged and counted -> US-145.
- Minimum fraction in the validator -> US-087 revised.
- Single in-flight frame sample, dropped ticks -> window service.
- Shortcut registration diffing -> input section.
- Clock protocol, scriptable fakes contract, reducer invariants, golden migration fixtures, Template names match the glossary -> Testing Decisions.

Not stolen, with reason: maintainer US-028 (deletion requires picking a replacement) is slower than the power-user draft's fall back to Priority Grid with a confirmation; platform US-083 and US-070 and maintainer `cooldown` state are attacked above.
