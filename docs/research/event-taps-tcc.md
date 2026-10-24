# Event taps, modifier detection and TCC permissions (research, 2026-10-23)

Scope: how Zones should watch window drags with Shift held, register global hotkeys, and survive TCC on macOS 14/15 (dev host here is macOS 27 SDK).
Tags: [Apple] primary doc/header, [DTS] Apple engineer forum post, [OSS] open-source code, [LOCAL] I ran it on this Mac, [UNVERIFIED] must be spiked.

## Findings

1. **Minimal permission set = Accessibility alone.** Zones needs Accessibility anyway (AX window move/resize). A DTS engineer says Accessibility grants both "post" and "listen", so a listen-only tap works once Accessibility is on; Input Monitoring is listen-only [DTS][S9]. Do not ask for Input Monitoring on top; DTS "couldn't think of a case" needing both [S9].
2. **Which TCC service gates which API** (the answer to the (a)-(d) matrix):
   - Listen-only/any CGEventTap: Input Monitoring (TCC `ListenEvent`), checkable with `CGPreflightListenEventAccess()`, requestable with `CGRequestListenEventAccess()` [DTS][S5][S6]. Accessibility also satisfies it [S9]. `.defaultTap` (can modify or drop) triggers the Accessibility prompt [forum user report, 2021][S7].
   - Keyboard taps: the SDK header says taps at HID/session/annotated points "may only receive key up and down events if access for assistive devices is enabled"; masked-out bits are cleared and an empty mask returns NULL [Apple][S2].
   - flagsChanged taps: no Apple text gives a separate rule; they are keyboard-class events. [UNVERIFIED] whether Input Monitoring-only suffices. Spike it.
   - Mouse-only listen-only tap: the header only gates key events [S2], but a Mojave-era thread claims all taps got gated [S8]. No primary source settles "mouse-only needs nothing". [UNVERIFIED] Spike on a clean VM with (none / Input Monitoring only / Accessibility only).
   - `NSEvent.addGlobalMonitorForEvents`: DTS says it "requires the Accessibility privilege" while taps need Input Monitoring "for weird historical reasons" (Jun 2022) [DTS][S5]. Apple's page: key events only monitorable if accessibility is enabled/trusted; observe-only; never called for your own app's events [Apple][S3]. A Jan 2026 thread shows it still working in a sandbox, so its exact gate is murky [DTS][S6]; treat it as Accessibility.
   - `NSEvent.modifierFlags` (class property) and `NSEvent.pressedMouseButtons`: documented as polling device state with no permission text [Apple][S4]. [UNVERIFIED] on a fresh machine.
3. **macOS 14 vs 15:** no Apple doc changes the above between them. Sequoia (15) changed only Carbon hotkeys (finding 12). A May 2026 macOS 15 report: listen-only tap returns nil before Accessibility is granted and the app often fails to appear in the Input Monitoring list; DTS answer: `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` is the "equivalent" request API, and the working tap after Accessibility is intended [DTS][S9].
4. **Tap options.** `kCGEventTapOptionListenOnly` = passive, cannot modify/divert; `kCGEventTapOptionDefault` = active filter. `kCGHIDEventTap` is root-only; use `kCGSessionEventTap` [Apple][S2]. Event masks are `1 << CGEventType.rawValue` (`CGEventMaskBit`) ORed together [S2].
5. **Exact re-enable pattern.** Header: "If a tap becomes unresponsive or a user requests taps be disabled, an appropriate kCGEventTapDisabled... event is passed to the registered CGEventTapCallBack. An event tap may be re-enabled by calling [CGEventTapEnable]" [Apple][S2]. Types: `tapDisabledByTimeout` (0xFFFFFFFE), `tapDisabledByUserInput` (0xFFFFFFFF) [S2]. Pattern, as implemented by both Rectangle and Loop:
   - In the callback: `if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { CGEvent.tapEnable(tap: port, enable: true); return Unmanaged.passUnretained(event) }` (Loop returns nil). Do not treat it as input; do not tear down inside the callback [OSS][S10][S11].
   - Loop rate-limits: more than 5 restarts in 2 s pauses 2 s then re-enables, to avoid a restart cascade [OSS][S11].
   - Backstop: `CGEventTapIsEnabled(tap)` on a slow timer (header exposes it) [S2]. SDL separates the auto-timeout (re-enable) from explicit disable by code or another program (stay off) [secondary][S14].
6. **Run loop / thread.** "The event tap callback runs from the CFRunLoop to which the tap CFMachPort is added as a source. Thread safety is defined by the CFRunLoop" [Apple][S2]. Recipe: `CFMachPortCreateRunLoopSource` then `CFRunLoopAddSource(runLoop, src, .commonModes)` then `tapEnable(true)` [S1][S11]. Rectangle and Loop both put taps on a dedicated `.userInteractive` thread, not main, and Rectangle hops to main with `DispatchQueue.main.async` for handling [OSS][S10][S11]. Loop adds a keep-alive source so `CFRunLoopRun()` does not exit [S11].
7. **Teardown.** `CFMachPortInvalidate(tap)`, not just release: CoreGraphics keeps internal refs, a merely disabled tap stays registered in WindowServer until process exit, and accumulated entries degrade system-wide input latency [OSS, Rectangle comment][S10]. Keep strong refs to the tap/thread (Hammerspoon taps silently died when GC'd) [secondary][S15].
8. **Latency at 120 Hz.** Frame budget is 8.33 ms/event. Apple publishes no timeout value or latency figure. [UNVERIFIED] threshold; I found no number. Apple does expose measurement: `CGGetEventTapList` returns per-tap `minUsecLatency/avgUsecLatency/maxUsecLatency`, reset on each call [Apple][S2]. Rule: callback does O(1) work (copy location/flags/timestamp, enqueue, return); all AX calls off-callback. Rectangle's callback only wraps and `async`-dispatches [OSS][S10]. Measure with `CGGetEventTapList` during a spike.
9. **"Window drag in progress" from mouse events alone is not reliable.** leftMouseDragged also occurs for text selection, scrollbars, resize, slider drags. Rectangle's approach [OSS][S12]:
   - `leftMouseDown`: record cursor, the window id from CGEvent field `.mouseEventWindowUnderMousePointerThatCanHandleThisEvent`, the AX frame and the WindowServer frame.
   - `leftMouseDragged`: after the baseline exists, compare frames from the SAME source ("AX and WindowServer can disagree during a drag"); `isMoving` = not resizing and origin changed; `isResizing` = size changed with 2+ shared edges. Retry window lookup up to 20 times, at least 0.1 s apart.
   - `leftMouseUp`: re-check "moved without resizing", because coalesced drags can leave the last drag sample stale.
10. **AX notification option.** Apple: `kAXWindowMovedNotification` "is sent at the end of the window-move operation, not during it" [Apple][S13], so it confirms a drag ended, it cannot drive live zone previews. AeroSpace uses an AXObserver moved callback gated by `NSEvent.pressedMouseButtons == 1` and focused-window equality, with no event tap at all [OSS][S16]. Best for Zones: tap for live state (down/drag/up + flags), frame-before/after as the decider, AX notification optional as a cross-check. [Judgment]
11. **Modifier state at mouse-up.** Two sources:
   - the mouse-up event's own flags: `CGEvent.flags` / `NSEvent.modifierFlags` (Rectangle reads `event.modifierFlags.intersection(.deviceIndependentFlagsMask)` on each event) [OSS][S12][S1b];
   - device state now: `NSEvent.modifierFlags` class property "returns the state of devices combined with synthesized events at the moment, independent of which events have been delivered" [Apple][S4], and `CGEventSource.flagsState(_:)` [Apple][S1b].
   Event-flags-at-up answers "was Shift down when released"; device state answers "now". For FancyZones semantics (Shift toggles during the drag), latch via `flagsChanged` in the tap, or read flags on every drag event, and read both sources at up. [Judgment]
12. **Global hotkeys: Carbon `RegisterEventHotKey` needs no permission.** sindresorhus/KeyboardShortcuts is built on it (`RegisterEventHotKey`, `InstallEventHandler`, `kEventHotKeyPressed`) and its FAQ says it triggers no permission dialogs and is sandbox/MAS compatible [OSS][S17]. Still available: the symbols are exported by HIToolbox in the macOS 27 SDK .tbd [LOCAL]. Deprecation status: the CLT SDK ships no Carbon headers and Apple's doc page did not render, so I could not confirm any deprecation attribute. [UNVERIFIED] Sequoia change: hotkeys with only Option or Option+Shift failed (error -9868) by deliberate change; Apple engineer (Sep 2024): "no workaround"; fixed in 15.2 beta 2 (Nov 2024); a Nov 2025 user says it still recurs [DTS][S18]. Mitigation: always include Command or Control. Event-tap hotkeys instead need Input Monitoring or Accessibility and cannot swallow keys unless `.defaultTap` (Accessibility); keyboard taps are blind under secure input [secondary][S15].
13. **Ad-hoc signing breaks the TCC grant on every rebuild.** An ad-hoc DR is `cdhash H"..."`. Apple TN3127: "Ad hoc signed code ... has a DR but it's tied to that specific version of the code... macOS can't reliably track the identity"; microphone example re-prompts after tweaking code [Apple][S19]. [LOCAL] two builds of the same ad-hoc bundle gave `designated => cdhash H"ebd713..."` then `H"07d9d7..."`.
14. **Stable signing keeps the grant.** Apple TN3127: a default Apple Development identity yields an identity-based DR (differs from Developer ID/MAS DRs) [Apple][S19]. [LOCAL] a self-signed code-signing cert gave an identical DR across two different binaries: `identifier "com.example.tcctest" and certificate leaf = H"cc2798..."`. Whether TCC then keeps the Accessibility toggle is [UNVERIFIED] here (no prompt run), but it is the keyed-on-DR mechanism TN3127 describes.
15. **`tccutil`**: `tccutil reset SERVICE [BUNDLE_ID]` "reset[s] all decisions for the specified service, causing apps to prompt again"; with a bundle id only that app [Apple man page][S20]. AeroSpace's debug script is literally `tccutil reset Accessibility bobko.AeroSpace.debug` [OSS][S16]. DTS names `ListenEvent` and `PostEvent` as TCC service names and says there "isn't a one-to-one relationship" with Settings rows [DTS][S21].

## Gotchas

- Omitting the bundle id resets that service for EVERY app. Always pass Zones' id [S20].
- `AXIsProcessTrusted()`/`CGPreflight*` do not reflect revocation of a running process; DTS: "accept the quit and relaunch" [DTS][S21]. Rectangle polls `AXIsProcessTrusted()` every 0.3 s until true, then proceeds [OSS][S22].
- `tapCreate` returns nil without permission (or an empty mask), including after revocation: treat nil as "no permission", not a crash [S2][S10].
- Input Monitoring-only gives `AXIsProcessTrusted() == false` (user report) so do not gate the whole app on AX if you ever rely on Input Monitoring [S7].
- TCC attributes a grant to the responsible process: running the binary from Terminal tests Terminal's grant, not yours (poster concluded this; Quinn pointed at "responsible code" docs) [DTS][S23]. Launch with `open Zones.app`.
- Cached TCC state on a dev Mac misleads: DTS says test permission flows on a fresh Mac/VM [DTS][S6].
- Rectangle's `canSnap` compares `flags & .deviceIndependentFlagsMask` with `!=` against the configured modifiers [S12]; that mask includes Caps Lock/Fn/numpad bits, so exact equality can fail when they are set (my inference). Mask to shift/control/option/command and test containment.
- Swift 6: the tap callback is `@convention(c)` and cannot capture; pass state via `userInfo` (`Unmanaged`), guard it with a lock/actor-safe box (Rectangle locks the port) [OSS][S10].
- `tapDisabledByUserInput` can mean the user or another process disabled it; re-enabling blindly is what Rectangle/Loop do, SDL does not [S10][S11][S14].
- Option-only hotkey bug (finding 12) is nondeterministic across 15.x per user reports.

## Implications for Zones

- Request ONLY Accessibility. Onboarding: `AXIsProcessTrustedWithOptions` with the prompt option [Apple][S24], poll like Rectangle, then start the tap. Skip Input Monitoring UI unless the spike proves a mouse+flagsChanged tap fails with Accessibility on.
- Input layer: one `.listenOnly` session tap at `.tailAppendEventTap` on a dedicated `.userInteractive` thread (Loop's shape) for leftMouseDown/Dragged/Up + flagsChanged; hop to the main actor with value-type snapshots. Fallback: Rectangle's NSEvent global+local monitor pair (simplest, main thread).
- Drag recognition: tap events for state, frame-before/after (same source) for decision, `pressedMouseButtons` for sanity, AX moved notification only as a cross-check.
- Modifiers: latch Shift from flagsChanged and per-drag event flags; at mouse-up consult the up-event flags and `CGEventSource.flagsState(.combinedSessionState)`; mask to the four real modifiers.
- Hotkeys: Carbon `RegisterEventHotKey` (via KeyboardShortcuts-style wrapper); default bindings must include Command or Control. No permission cost. Keep the event tap for drag only.
- Resilience: implement the re-enable pattern with Loop's rate limiter, `CFMachPortInvalidate` on teardown, a `CGEventTapIsEnabled` watchdog, and a nil-tap path that returns to the permission screen.
- Dev loop (decisive): never ship dev builds ad-hoc. Create one stable identity once: Xcode > Settings > Accounts > Apple Development (free Personal Team) if available; otherwise Keychain Access > Certificate Assistant > Create a Certificate (Code Signing, name "Zones Dev"). Then `codesign --force --sign "Zones Dev" --identifier <bundle-id> Zones.app` in the build script, build to a fixed path, launch with `open`. Verify with `codesign -d -r- Zones.app` that the DR has no `cdhash`. Keep a `scripts/reset-tcc.sh` doing `tccutil reset Accessibility <bundle-id>` for recovery only. No signing identities exist on this Mac today (`security find-identity -v -p codesigning` = 0).
- Phase-0 spikes to close UNVERIFIED items: (a) clean-VM matrix for mouse-only and flagsChanged listen-only taps, (b) measure tap latency via `CGGetEventTapList` during a 120 Hz drag, (c) confirm the self-signed cert keeps the Accessibility toggle across 3 rebuilds, (d) confirm `NSEvent.modifierFlags` needs no permission.

## Sources

- S1 https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)  ; S1b https://developer.apple.com/documentation/coregraphics/cgeventsource/flagsstate(_:) and https://developer.apple.com/documentation/coregraphics/cgevent/flags
- S2 SDK header `CGEvent.h` / `CGEventTypes.h` (MacOSX.sdk/System/Library/Frameworks/CoreGraphics.framework/Versions/A/Headers/), read locally; text quoted from CGEventTapCreate, CGEventTapEnable, CGGetEventTapList, CGPreflightListenEventAccess
- S3 https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)
- S4 https://developer.apple.com/documentation/appkit/nsevent/modifierflags-swift.type.property ; https://developer.apple.com/documentation/appkit/nsevent/pressedmousebuttons
- S5 https://developer.apple.com/forums/thread/707680 (Quinn, Jun 2022)
- S6 https://developer.apple.com/forums/thread/811443 (Quinn, Jan 2026)
- S7 https://developer.apple.com/forums/thread/122492 (user posts, 2019-2021, not DTS)
- S8 https://developer.apple.com/forums/thread/693727 (via search snippet; secondary)
- S9 https://developer.apple.com/forums/thread/828052 (Kevin Elliott, DTS, May 2026, macOS 15)
- S10 https://github.com/rxhanson/Rectangle/blob/7c5c9c56b447dad4e3720b805e54b1d115b1a90e/Rectangle/Utilities/EventMonitor.swift
- S11 https://github.com/MrKai77/Loop/tree/573ace3071641bbe002527ccfc0811842300ccba/Loop/Utilities/Event%20Monitoring (BaseEventTapMonitor, PassiveEventMonitor, EventTapThread)
- S12 https://github.com/rxhanson/Rectangle/blob/7c5c9c56b447dad4e3720b805e54b1d115b1a90e/Rectangle/Snapping/SnappingManager.swift
- S13 https://developer.apple.com/documentation/applicationservices/kaxwindowmovednotification
- S14 https://git.axiodl.com/encounter/SDL/commit/51ccc9ed8cab7bf1e3ea293328f2e382eceaf273 ; https://lists.apple.com/archives/Cocoa-dev/2010/Sep/msg00892.html (search snippet only; fetch 502)
- S15 https://github.com/Hammerspoon/hammerspoon/issues/1103 ; https://www.hammerspoon.org/docs/hs.eventtap
- S16 https://github.com/nikitabobko/AeroSpace/blob/74a1bf17e82d70e0a21945ba04bb4f590bf19f83/Sources/AppBundle/mouse/moveWithMouse.swift ; .../mouse/mouse.swift ; .../script/reset-accessibility-permission-for-debug.sh
- S17 https://github.com/sindresorhus/KeyboardShortcuts (README FAQ) ; Sources/KeyboardShortcuts/HotKey.swift @772133d9dbe800fdac0473226822994c5c162c58
- S18 https://developer.apple.com/forums/thread/763878 (Apple Frameworks Engineer, Sep and Nov 2024)
- S19 https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements
- S20 `man tccutil` (local, Darwin, 2012 page) ; S21 https://developer.apple.com/forums/thread/735204 (Quinn)
- S22 https://github.com/rxhanson/Rectangle/blob/7c5c9c56b447dad4e3720b805e54b1d115b1a90e/Rectangle/AccessibilityAuthorization/AccessibilityAuthorization.swift
- S23 https://developer.apple.com/forums/thread/741622 ; S24 https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions
- Apple Support, Input Monitoring toggle: https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4cedafb6/mac
- [LOCAL] experiments: `codesign -d -r-` on ad-hoc vs self-signed builds of a stub bundle, 2026-10-23 (temp keychain deleted)
