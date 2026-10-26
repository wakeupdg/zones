# Round 1 critique — from the platform persona

Scope: attacks on the power-user and maintainer drafts, judged against the locked ADRs, CONTEXT.md, the six research "Implications" and "Gotchas" sections, and what real Macs do. Each attack names the story or decision, says why it fails, and proposes a fix the synthesizer can lift verbatim.

## Attacks on power-user

1. **US-017 ("Overlay within one frame of pressing the modifier").** ADR-0006 confirms a window move by polling the frame at about 60 Hz before anything is shown; the Overlay cannot appear on the modifier press itself without also flashing on a Shift-click that never moves (which US-016 and this persona's own US-042-equivalent forbid). As written the story is untestable and contradicts the draft's own `pressed -> moving` gate. Fix: "within one display refresh of the later of (modifier down, move confirmed)"; measure the arm latency from the first frame sample that differs, not from the key event.

2. **US-034 and the `armed` rule "a release-and-press clears" the Span.** Three drafts give three semantics for releasing the Span Modifier (clear on re-press, revert to single Zone, freeze). Clearing on re-press punishes key bounce (Control on mechanical keyboards chatters) and a three-key drop (Shift+Control+button held) is hard on a trackpad. ADR-0008 says only that Zones touched while the key is down accumulate. Fix: release freezes the accumulated Span; re-press resumes accumulating into the same set; the escape hatch is releasing the Activation Modifier (already clears everything) and re-pressing. Record this as the single Span rule.

3. **US-035 ("Span cleared if I cross to another Display").** Skimming a seam during a cross-Display drag silently throws away the Span; coming back does not bring it back. Scoping a Span to one Display is right (a size write is clamped to the Display it lands on), clearing is lossy. Fix: the Span keeps its DisplayKey and is suspended while the cursor is on another Display (Zones there are not accumulated; the drop uses the Zone under the cursor); returning to the Span's Display resumes it.

4. **US-041 ("size the window correctly on a Display with a different scale factor").** AX positions and sizes are in points; scale factor cannot change the result. The real cross-Display hazard is size clamping to the source Display, which ADR-0022's size-position-size order already handles. A tester following this story hunts for a bug that cannot exist and misses the clamp. Fix: reword to "a Snap across Displays lands at the Zone's point size because the size is written again after the position"; keep the 2x-to-1x case as a manual matrix row.

5. **Window registry `placement` "cleared when an observer reports a move Zones did not issue" plus the cycle rule in US-058.** Research says moved and resized notifications fire at gesture end and may not fire at all for some apps (unverified), so a stored `placement` goes stale after a hand move and the next cycle starts from a wrong base. The 1 Hz resync added as a safety net contradicts US-117 ("no polling at all while idle"). Fix: do not store placement; at command time, read the frame back and pick the Zone whose rect best matches it (the platform and maintainer drafts both do this). Observers then serve only `destroyed` bookkeeping, and the 1 Hz resync disappears.

6. **US-117 ("no polling at all while idle").** The draft's own implementation needs the AXIsProcessTrusted poll while not granted (ADR-0021), a tap watchdog, and the 1 Hz resync above. The story is false as stated and will be "verified" by nobody. Fix: enumerate the idle timers precisely: trust poll only while not granted; tap health check at 2 s; no AX reads while idle except a low-rate heartbeat used for revocation detection (see attack 13); zero timers otherwise.

7. **US-105 ("Shift already down in Finder ... still arm").** Zones' tap is listen-only, so Finder sees the Shift regardless; the Overlay appears only after the frame moves, so Shift-click selection is untouched. The story conflates a title-bar drag with a content drag (which is not a Drag Session because the window frame does not change) and "still arm" names no observable. Fix: "a title-bar drag begun with Shift already down arms once the frame moves; Zones never consumes the modifier, so the app's own Shift semantics still apply; a content drag never shows the Overlay."

8. **US-111 ("two same-size stacked windows: the one I grabbed moves") versus US-030 (fail closed).** The CGWindowID from the event identifies the top window, but matching it to an AX element by pid and frame yields two identical candidates and no public API says which AX element is frontmost. As written US-111 is unsatisfiable by the draft's own matcher, and US-030 then fails closed on every stacked pair. Fix: hold both candidates through `pressed`; on the first frame sample, the candidate whose frame changed is the dragged window; if none or both changed, fail closed. The disambiguation costs one extra AX read and resolves the common case.

9. **`resolve` rounding "to whole points, with the last Zone absorbing rounding".** On a 2x Display the backing grid is half a point; rounding to whole points leaves one-pixel seams at Gap 0 and makes the Overlay rect and the written frame disagree by a pixel. Fix: round to the Display's backing grid (1 divided by scale) and carry the remainder to the last Zone on each axis.

10. **US-065 ("shortcuts work without the mouse tap being alive").** Carbon hotkeys fire, but the window commands still need the Accessibility grant to read and write frames. If the tap died because the grant was revoked, every window shortcut silently no-ops and the story reads as satisfied. Fix: split it: editor and Settings shortcuts need nothing; window shortcuts need Accessibility but not the tap; the General pane says which of the two is missing.

11. **US-022 ("Overlay works over a full-screen app's Space when I drag a non-full-screen window there").** Whether macOS lets a managed window travel onto a Display whose active Space is full-screen, and what `visibleFrame` reports there, is explicitly unverified in the overlay and Spaces research. The story promises an outcome the spikes have not confirmed. Fix: gate it on the overlay spike; specify the fallback (Overlay shows on that Display only if the panel is visible there; the drop uses that Display's fresh `visibleFrame`), and list "menu bar auto-hidden" as a manual check.

12. **"Snap: three AX writes and one read."** The ADR-0022 protocol is read EUI, set EUI off, size, position, size, read position, read size, restore EUI: up to eight round trips. Under the 250 ms timeout the hung-app worst case is 2 s, not 1 s, and the budget drives the cooldown design. Fix: count eight, skip the EUI pair when the attribute is absent or already off, and state the worst case.

13. **Permission machine "on regain, the tap is recreated without a relaunch".** The event-taps research records Apple DTS saying the trusted probe does not reflect revocation of a running process and that the fix is quit and relaunch. Promising an in-process recovery that cannot be tested on the build machine will ship a dead "re-granted" state. Fix: add a `needsRelaunch` state entered when the probe reports trusted again while tap creation still fails, with a "Quit and Reopen" button; recover in-process only if the tap actually comes back.

14. **US-087 ("minimum 120x80 points at the reference Display").** "Reference Display" is undefined and a point minimum on one Display is violated on a smaller one, so the validator result depends on where the editor happens to be open. Fix: the validator enforces a minimum fraction per axis (the maintainer draft's rule); the editor shows the resulting point size for the Display being edited as information only.

15. **Focus Template "inert leaves".** A leaf that is not a Zone contradicts ADR-0003 (zones are the leaves), ADR-0004 (numbering over zones) and CONTEXT (a Zone is a rectangle a window can be snapped into). The draft introduces this in Implementation Decisions and only half-acknowledges it in C4 (filed against ADR-0005, not ADR-0003). Fix: file it as a challenge to ADR-0003 and let the decision ticket pick between the maintainer's 20/60/20 and a Layout-level normalized surround fraction (see the platform draft's Challenges); do not ship a third leaf kind.

16. **`moving` entered when "origin moved with size unchanged"; "size change with origin fixed is a resize".** A resize from the top or left edge changes the origin and the size, so it falls through both rules and is treated as a move. Fix: any size change (beyond tolerance) ends the session as a resize; a move is origin changed and size unchanged.

17. **US-114 (first-use modifier hint drawn on the Overlay).** Not in the BRIEF, needs a persisted counter and a text layer at arbitrary opacity on a surface that is hidden from VoiceOver by design, so the teaching text is invisible to the users who most need it. Fix: keep the cheat sheet in onboarding (US-113) and in the General pane as key caps; drop text from the Overlay in v1.

18. **US-115 ("Snap completes within 50 ms of mouse-up").** The number is dominated by the target app, is unmeasurable headless, and fails in Chrome on a busy machine regardless of Zones' code. Fix: budget Zones' own work (Overlay hidden and first AX write issued within 2 ms of mouse-up, verifiable with a fake), and record per-app wall time in the manual matrix.

## Attacks on maintainer

1. **HitTester "none for points in Margin, Gap, or outside visibleFrame" plus Challenge 3's proposal to ship a non-zero default Gap so the Restore path exists.** This makes an 8-point miss teleport the window back to its Original Frame. Every FancyZones user will file it as a bug on day one; the other two drafts both chose nearest-Zone for Gap and Margin. Fix: `nearest` for Gap and Margin, `none` only outside `visibleFrame`; the mouse Restore path is the menu bar and Dock strips, which exist on every Display without relying on Appearance defaults.

2. **Focus as "three columns 20/60/20 with the center as Zone Number 2".** This changes what the user sees: Focus becomes a three-Zone Layout where Control+Option+1 sends a window to a 20 percent sliver, and the Zone the Template is named for is number 2. It contradicts ADR-0005's "one center zone" as much as inert leaves contradict ADR-0003. Fix: present it as one option of a decision ticket alongside a Layout-level normalized surround fraction (tree tiles the Layout rectangle; Focus is one Zone, Zone Number 1; drops in the surround go to the nearest, only, Zone). Either way the Templates ticket must wait on the decision.

3. **Permission state `revoked(badge, onboarding visible, relaunch offered)`.** Offering relaunch while the grant is still absent relaunches into an untrusted app and teaches the user the button does nothing. Fix: split `revoked` (grant absent: badge, onboarding, no relaunch button) from `needsRelaunch` (probe trusted again, tap creation still nil: offer "Quit and Reopen").

4. **"The probe alone is never used to detect revocation" with no replacement while idle.** Revocation then surfaces only at the next mouse-down, when the first AX read fails; the badge the ADR-0021 promises can be minutes late. Fix: a low-rate heartbeat on the WindowActor (one trivial AX read of the system-wide element's focused application every 5 s while trusted); `apiDisabled` from the heartbeat is a revocation signal.

5. **InputSource as an AsyncStream hopped to the main actor.** With default buffering, a 120 Hz drag queues `mouseDragged` events whenever the main actor is busy (menu open, SwiftUI update); the reducer then replays stale cursor positions and the highlight trails the cursor. Fix: coalesce `mouseDragged` to the newest sample (buffer policy newest-one) on a channel separate from `mouseDown`, `mouseUp` and `flagsChanged`, which are never dropped.

6. **ExclusionPolicy reason `notSettable` versus SnapPlan's "whether size is settable".** The policy skips any window whose size or position is not settable (ADR-0018 wording), so a fixed-size window with a settable position (Calculator, many utility panels) never reaches the planner that knows how to place it. Fix: skip only when position is not settable; when size is not settable the plan is position-only, top-left aligned. File the ADR-0018 refinement explicitly.

7. **RestoreLedger "keeps the entry so Restore still works after a later re-Snap".** Sequence: Snap, Restore, hand-move to a new place, Snap, Restore. The user expects the hand-moved frame; the ledger returns the frame from before the first Snap. Fix: a successful Restore removes the entry; the window is back in its pre-Snap state, so the next Snap is a first Snap again and captures the current frame.

8. **`armed` "accumulating the swept set while the Span Modifier is down and replacing it otherwise".** Releasing Control before the mouse button collapses a three-Zone Span to the Zone under the cursor on the next event, so the drop requires holding Shift, Control and the button together. Fix: freeze on release (see power-user attack 2); replacement happens only when the Activation Modifier is released and re-pressed.

9. **DisplaySnapshot key "UUID string with vendor-model-serial fallback".** Two identical Displays with serial 0 (common on cheap panels) collide on the fallback and share one Assignment that flips each time the arrangement changes. Fix: a fallback key is marked unstable and never persisted; an unstable Display uses the default Template and the Layouts pane says why.

10. **Preferences "stored as one Codable value in UserDefaults".** One undecodable field (a new enum case after a downgrade, a hand edit) resets every preference including shortcuts and exclusions. Fix: decode field by field with per-field defaults, or store one key per field under the namespace, and keep the schema version for migrations; add a test that a document with one unknown value loses only that value.

11. **Persistence actor "with a coalescing debounce so editor drags do not write per pixel".** US-031 already applies edits only on Save, so there are no per-pixel writes; the debounce solves nothing and opens a window where a pending write is lost on quit or crash. Fix: write synchronously (atomic temp-and-rename) on Save, on Assignment change and on import; flush on quit; no debounce.

12. **"Mirror groups collapse to one DisplayKey" without saying which.** If the chosen key differs between sessions, the mirrored set's Assignment flips. Fix: the key of the mirror master (the Display in the set that mirrors nothing), and no new Assignments are persisted while mirroring is active.

13. **CI gate "a grep gate that the App target contains no force unwraps".** A grep for `!` matches `!=`, boolean negation and string literals; it will either be disabled in week one or quietly weakened. Fix: gate on `try!`, `as!` and `fatalError(` only, with a per-line allow marker, and leave implicit unwraps to review.

14. **US-088 ("Zones do nothing visible when the cursor is over the menu bar or Dock strip").** The panels cover the whole Display and stay visible; what changes is that the highlight clears and the drop would Restore. "Nothing visible" is the opposite of what the user sees and cannot be tested. Fix: "the highlight clears and the Overlay stays; a drop there Restores".

15. **Reducer event `frameSample(handle, frame)` with "a single in-flight sample" but no resize rule for edge resizes.** `pending -> idle` fires only "when a frameSample shows only a size change"; a top-left resize changes origin and size and becomes a move. Fix: any size delta ends the session (same as power-user attack 16).

16. **Diagnostics report includes Preferences and every recent event's bundle identifier.** The exclusions set and the Snap log together list the apps the user runs; pasting it into a public issue is less "safe" than US-084 claims. Fix: show the report in a window before copying, and group bundle identifiers so the user can see what they are sharing; keep the "no titles" guarantee.

## Steal list

Items the other drafts got right that the platform draft lacked; all are folded into the revised platform draft.

From power-user:
- Resize gestures are never Drag Sessions (US-027); any size change ends the session.
- Span scoped to one Display (US-035), adopted as "suspended, not cleared".
- A second mouse-down during a Drag Session is ignored (US-108).
- Settings General shows permission and tap state (US-110) and the menu-bar badge covers tap loss (US-120).
- Snap is idempotent: same Zone again changes nothing and never touches the Original Frame (US-112).
- Imported Assignments for absent Displays stay dormant until the Display appears (US-100).
- A corrupt data file is moved aside with a timestamp, never discarded (US-101).
- Overlay hides on mouse-up before the AX writes begin, so a slow app never delays the Overlay going away.
- Cheat sheet at the end of onboarding (US-113); modifiers shown as key caps in General.
- Import refuses newer document versions with a message naming the versions (US-099).
- Cycle from no matching Zone: Right starts at 1, Left at the last Zone (US-059).
- Layout management: duplicate a Template into a custom Layout, rename, delete with fallback (US-070, US-071, US-075).
- Editor ergonomics: divider snapping to halves, thirds, quarters and collinear dividers with a free-drag modifier; arrow nudging; keyboard split (US-077 to US-079).
- Exclusions pane shows the bundle identifier (US-096).
- Idle performance budget stated as an invariant (US-116, US-117, corrected per attack 6).

From maintainer:
- The menu opens instantly while a target app hangs (US-009): menu construction never waits on the WindowActor.
- Editor applies on Save, Cancel discards (US-031); Layout delete blocked without a replacement (US-028).
- A data file from a newer Zones is left untouched and reported (US-081).
- Copy Diagnostics as one block with app and macOS versions, Displays, Assignments, preferences and events (US-083), and skip reasons counted (ExclusionPolicy).
- Preferences carry a schema version (US-089).
- One in-flight frame sample; a tick while a sample is outstanding is dropped (WindowActor).
- `FrameWriteResult` gains `timedOut` and `elementGone`.
- Effects-as-values reducer so the Drag Session is testable without the OS.
- Shortcut registration diffing: only changed shortcuts re-register.
- Clock protocol so cooldowns and debounces test instantly.
- Fixture-hash gate on golden documents; migration test from every older golden version.
- `EnhancedUIPolicy` as a value (toggle, leave, auto) so a default flip is not a rewrite.
- ADR-0013 contingency: an optional Space token on Assignment and a version-2 migration if the spike passes.
- `separateSpaces` flag on DisplaySnapshot.
