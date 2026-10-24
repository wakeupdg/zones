# AXUIElement window move/resize limits

Researched 2026-10-23. Source tags like [H1] point to the Sources list at the bottom.
Header paths are under `HIServices.framework/Headers/` in the macOS 26.5 CLT SDK (the 14.5 SDK copy of
`AXAttributeConstants.h` has no `#define`s, so constants were read from 26.5).
Claims marked **(unverified)** came from memory or secondary sources and need a local experiment.

## Findings

1. **Move/resize = two separate attribute writes.** Build `AXValueCreate(.cgPoint, &pt)` / `(.cgSize, &sz)` and call
   `AXUIElementSetAttributeValue(win, kAXPositionAttribute | kAXSizeAttribute, value)` [H1][H2]. There is no
   atomic "set frame": kAXFrameAttribute is not in the public header [H2]. Rectangle's own comment: "The Accessebility API
   only allows size & position adjustments individually" [R1].
2. **Order that works: size, position, size.** Rectangle: "To handle moving to different displays, we have to adjust
   the size then the position, then the size again" [R1]. AeroSpace does the same: "Set size and then the position. The order is
   important", then size again when a position was given [A1]. Reason: macOS/the app clamps size to the window's *current*
   display, so a cross-display move needs the final size re-applied after landing [R1]. After a move, a size refusal can also be
   transient until the window is on-screen [R1].
3. **Verify by read-back.** Rectangle's `setImmediateFrame` sets size, reads `frame` back, and if width/height differ
   by more than 1 pt it treats it as a minimum/maximum-size clamp and re-places the window using the size actually accepted [R1].
   AX writes return `.success` even when the app clamped, so success != the requested frame.
4. **Which windows refuse (detection):**
   - Non-resizable: check `AXUIElementIsAttributeSettable(win, kAXSizeAttribute, &b)`. Rectangle's `isResizable()` does exactly this
     and defaults to `true` if the call itself fails [R1][H3]. Do the same check on `kAXPositionAttribute`.
   - Header: position/size are "Generally no [writable]... some elements that can be moved... (like windows) should offer a writable
     position attribute", i.e. apps may opt out [H2].
   - Not a real window: `kAXRoleAttribute` != `kAXWindowRole`, or role is `kAXSheetRole` / `kAXPopoverRole` / `kAXDrawerRole` [H4].
     AeroSpace classifies "popup" (role is not a window) vs "dialog" (subrole != `kAXStandardWindowSubrole`) vs window [A2].
     Subroles in header: Standard, Dialog, SystemDialog, FloatingWindow, SystemFloatingWindow [H4].
   - AeroSpace's dialog heuristic also treats a window as non-tileable when its full-screen button is absent/disabled
     (Calculator, System Settings, Finder copy dialog, PiP windows), with per-app exceptions (Chrome, iTerm2, Alacritty, kitty, VS Code,
     Gimp, Activity Monitor...) [A2]. Minimized windows and windows of hidden apps report subrole `AXDialog` [A2].
   - Full screen: attribute name `"AXFullScreen"` is used by Loop but is not in the public header [L1]. Rectangle instead infers it
     from the window's zoom/full-screen button state [R1]. Moving a native full-screen window is not meaningful; skip it.
   - Min/max size: no AX attribute exposes them. Only way is to try and read back (finding 3) [R1].
5. **Coordinates.** AX position is "global screen position of the top-left corner... 0,0 is the top-left corner of the screen that
   displays the menu bar... vertical axis increases downward" [H2]. `AXUIElementCopyElementAtPosition` takes "top-left relative screen
   coordinates" [H5]. `CGWindowListCopyWindowInfo` bounds use "origin at the upper-left corner of the main display" [C1].
   AppKit/NSScreen is bottom-left origin anchored at the menu-bar screen [D1]. Convert with the primary screen height:
   `y_ax = NSScreen.screens[0].frame.maxY - y_cocoa` (point) and `y_ax = primaryMaxY - rect.maxY` (rect, size unchanged). Rectangle's
   `CGPoint/CGRect.screenFlipped` is exactly this [R2]. Use `screens[0]` (the menu-bar screen), never `NSScreen.main` (key-window
   screen) [R2][D1]. Displays above/left of primary give negative AX coordinates (follows from top-left-of-primary origin [H2][D1]).
6. **Timeouts / hung apps.** `AXUIElementSetMessagingTimeout(el, seconds)`: pass the system-wide element to set the process-wide default;
   per-element timeouts apply only to that element object; `0` resets to default; values must be positive [H6]. A
   `kAXErrorCannotComplete` ("messaging has failed in some way", often a timeout) means "repeat the request or change the timeout" [H3][H5].
   Rectangle exposes a per-element helper: "Caps how long AX calls through this element can block on an unresponsive app (the systemwide
   default is several seconds)" [R1]. AX calls are synchronous IPC to the target app, so a hung app blocks the caller.
7. **AXEnhancedUserInterface.** Not in the public headers (grep of `AXAttributeConstants.h` found nothing); apps/WMs use the raw string
   `"AXEnhancedUserInterface"` on the *application* element [L1]. When some apps turn it on (VoiceOver and other AT do), window moves
   animate and Chrome can end up mispositioned or slow [RD1][P1][RI1]. Rectangle reads it, sets it false before frame changes, then restores
   it, with modes: 1 always restore, 2 never restore, 3 also disable on app switch, 4 (default) auto - leave it off for Chromium browsers,
   restore for others, restore if VoiceOver/Switch Control is on [R1][RD1]. AeroSpace does the same with a `defer` restore [A1]. Phoenix cited
   "Chrome doing odd animations and ending up in incorrect position" but could not reproduce on a later release (PR closed) [P1].
8. **Focused window.** `AXUIElementCreateSystemWide()` -> `kAXFocusedUIElementAttribute` (then walk to `kAXWindowAttribute`), or
   `NSWorkspace.shared.frontmostApplication.processIdentifier` -> `AXUIElementCreateApplication(pid)` -> `kAXFocusedWindowAttribute`
   [H4][R1]. Rectangle's fallback chain: focused window of frontmost app -> first of `kAXWindowsAttribute` -> system-wide focused element's
   window -> first CGWindowList entry [R1]. Window under a point: `AXUIElementCopyElementAtPosition(systemWide, x, y, &el)` (z-order hit-test,
   not restricted to one app when given the system-wide element) then take `kAXWindowAttribute` / walk parents until role == window [H5][R1].
   Errors: `kAXErrorNoValue` = nothing there [H5]. Rectangle also tries per-app windows by frame and falls back to the smallest window containing
   the point [R1]. Hit-test also returns menu bar items, desktop, Dock; filter by role.
9. **Stable window id.** `_AXUIElementGetWindow(AXUIElementRef, uint32_t*)` is private, declared by hand in bridging headers by Rectangle,
   AeroSpace and Loop [R3][A3][L1]. Public-only alternatives, in order: (a) keep the `AXUIElement` itself as identity - `CFEqual`/`CFHash` are stable
   per window across moves/resizes (Rectangle's last-resort id uses `CFHash`, high bit set to avoid collision with real ids) [R1]; (b) match
   `CGWindowListCopyWindowInfo` entries (`kCGWindowNumber`, `kCGWindowOwnerPID`, `kCGWindowBounds`) by pid + frame - Rectangle takes the first
   match and admits "there's no real way to guarantee which window we're actually getting" [R1][C1]; (c) `kCGWindowName` as tiebreaker, but names
   may be absent ("If present, the name of the window") [C1] and reading them needs Screen Recording permission **(unverified)**.
10. **Drag detection.** `kAXWindowMovedNotification` / `kAXWindowResizedNotification`: header says "sent at the end of the window move, not
    continuously" [H7]; the notification value is the moved window element [H7]. `kAXUIElementDestroyedNotification`: the element is
    invalid afterwards, only `CFEqual` is safe [H7]. Setup: `AXObserverCreate(pid,...)`, `AXObserverAddNotification(obs, el, name, refcon)`,
    add `AXObserverGetRunLoopSource` to a run loop; one observer per app pid [H8]. Errors to handle: `NotificationAlreadyRegistered`,
    `NotificationUnsupported`, `CannotComplete` [H8]. AeroSpace observes `kAXMovedNotification`/`kAXResizedNotification` per window plus
    `kAXUIElementDestroyedNotification`, miniaturize/deminiaturize on windows, and `kAXWindowCreatedNotification`/`kAXFocusedWindowChangedNotification`
    on the app [A4][A5]. Loop and Rectangle do NOT use AXObserver for live drag: they use mouse event monitors (`leftMouseDragged`/`leftMouseUp`)
    and poll the dragged window's AX frame [LD1][RS1].
11. **TCC.** Needs Accessibility permission. `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` returns the *current* trust and
    "Prompting occurs asynchronously and does not affect the return value" [H9]. Without trust, AX calls fail with `kAXErrorAPIDisabled`
    (-25211) [E1]. Rectangle polls `AXIsProcessTrusted()` on a 0.3 s timer until granted [R4]. Trust is per code-identity, so ad-hoc re-signed
    dev builds may need the user to re-grant **(unverified)**.

## Gotchas

- `.success` != applied: apps clamp silently (min/max size, screen edge, Dock). Always read back (F3).
- Size-clamping to the current display: cross-display move needs size->position->size (F2).
- Do not call `AXUIElementSetAttributeValue` on the main thread without a short timeout: one hung app freezes your UI (F6). Use a background
  serial queue per app (AeroSpace uses one AX thread per app [A5]) and `SetMessagingTimeout` ~0.25-1 s **(value is a recommendation)**.
- Enhanced-UI toggling is itself an AX write to the app element and can fail/beat the frame write; restore even on error path (use `defer`) [A1].
- CFRunLoop sources for observers must live on a thread whose run loop runs; AeroSpace adds them in `.defaultMode` on the current loop [A5].
- Window ids from `_AXUIElementGetWindow` can be unavailable on some windows; Rectangle needed a derived-id fallback (issue #640 ref in code) [R1].
- `AXUIElementCopyElementAtPosition` takes `Float`, not `CGFloat` [H5]; Rectangle casts `Float(position.x)` [R4].
- Stale `AXUIElement`s: `kAXErrorInvalidUIElement` after a window closes; drop from cache on `kAXUIElementDestroyedNotification` [H7].
- Sheets/popovers/panels appear as windows in `kAXWindowsAttribute` for some apps; always gate on role+subrole before snapping [A2].
- Moved/Resized notifications are documented end-of-gesture only; real apps may fire more often **(unverified)**. Do not depend on either behaviour.

## Implications for Zones

1. Wrap AX in one `WindowController` actor/queue: `setFrame(win, rect, mode)` = [disable AXEnhancedUserInterface if on] -> size -> position -> size ->
   read back `kAXPositionAttribute`/`kAXSizeAttribute` -> restore EUI via `defer`. Return `.applied(actual)` / `.clamped(actual)` / `.refused(AXError)`.
2. Skip size write if `IsAttributeSettable(kAXSizeAttribute)` is false (still try position). Skip windows with role != window, subrole not in
   {Standard, Dialog?}, or `AXFullScreen == true`; default dialogs/floating to "do not snap" with a user override list (bundle id).
3. If read-back size > zone, accept it and position so the window stays on-screen (align to zone's top-left, or center) instead of retrying forever.
4. Keep ONE conversion util: `appKitRect -> axRect` using `NSScreen.screens[0].frame.maxY`, and `axRect -> NSScreen` by max intersection area.
   Store zone layouts per display in display-relative fractions; resolve to AX global coords only at apply time (display hot-plug safe).
   Unit-test with a mock screen set including a display above and left of primary (negative coordinates).
5. Set a process-wide timeout at launch (`AXUIElementSetMessagingTimeout(systemWide, 1.0)`) and a short per-app one (0.25-0.5 s) for drag-time reads.
   Treat `CannotComplete` as "retry once, then mark app unresponsive for N seconds".
6. Identity: use `CFHash`/`CFEqual` of the `AXUIElement` as the in-memory key; use CGWindowList (pid + frame, then title) only to map to
   overlay/Spaces data. Do not ship `_AXUIElementGetWindow` (requirement: no private APIs); budget for ambiguous-match cases (two same-size windows).
7. Drag detection: use `NSEvent.addGlobalMonitorForEvents` (or a listen-only CGEventTap) for `leftMouseDown/Dragged/Up` + modifier state; on first drag
   resolve the window under the cursor via `CopyElementAtPosition`, then poll its AX frame (cheap, on the AX queue) to detect move vs resize vs click.
   Use `AXObserver` (moved/resized/destroyed/created/focused-window-changed) for post-hoc bookkeeping (re-snap on resize, cache invalidation), not for the
   live drag preview. Measure real notification cadence in a spike before relying on it.
8. Permissions: on launch call `AXIsProcessTrustedWithOptions(prompt:false)`; show onboarding; poll `AXIsProcessTrusted()` every ~0.3-1 s until true
   (as Rectangle does [R4]); never cache "trusted". Handle `kAXErrorAPIDisabled` at runtime (user revoked mid-session).
9. Add an Advanced default `enhancedUI` mode mirroring Rectangle's 1-4 semantics; default to "auto" (leave off for Chromium/Electron, restore for others
   if VoiceOver is on).
10. Spike tests (manual, local): Chrome, Safari, Terminal, Finder, System Settings, Calculator, a 1Password-style panel, an Electron app, a fullscreen app,
    an unresponsive app (SIGSTOP) - verify read-back behaviour, timeouts, and EUI side effects on macOS 14 and 15+.

## Sources

Local headers (macOS 26.5 CLT SDK, `.../ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Headers/`):
- [H1] `AXUIElement.h` `AXUIElementSetAttributeValue` (lines ~207-223); `AXValue.h` `AXValueCreate`, `kAXValueTypeCGPoint/CGSize`
- [H2] `AXAttributeConstants.h` `kAXPositionAttribute` (~609-625), `kAXSizeAttribute` (~629-641)
- [H3] `AXUIElement.h` `AXUIElementIsAttributeSettable` (~188-204)
- [H4] `AXAttributeConstants.h` `kAXFocusedWindowAttribute`/`kAXFocusedUIElementAttribute`/`kAXWindowsAttribute` (~1004-1009), `kAXWindowAttribute`;
  `AXRoleConstants.h` `kAXWindowRole`, `kAXSheetRole`, `kAXDrawerRole`, `kAXPopoverRole`, `kAXStandardWindowSubrole`... (~414-418)
- [H5] `AXUIElement.h` `AXUIElementCopyElementAtPosition` (~334-353)
- [H6] `AXUIElement.h` `AXUIElementSetMessagingTimeout` (~387-402)
- [H7] `AXNotificationConstants.h` `kAXWindowMovedNotification`/`kAXWindowResizedNotification` (~116-133), `kAXUIElementDestroyedNotification` (~186-194)
- [H8] `AXUIElement.h` `AXObserverCreate`/`AXObserverAddNotification` (~590-625)
- [H9] `AXUIElement.h` `AXIsProcessTrustedWithOptions` (~55-66)
- [E1] `AXError.h` (`kAXErrorCannotComplete -25204`, `kAXErrorAPIDisabled -25211`, `kAXErrorNoValue -25212`, ...)
- [C1] `CoreGraphics.framework/Headers/CGWindow.h` `kCGWindowBounds`, `kCGWindowName`, `kCGWindowNumber`, `kCGWindowOwnerPID`
- [D1] https://developer.apple.com/documentation/appkit/nsscreen ; https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/QuartzDisplayServicesConceptual/Articles/Overview.html ; https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaDrawingGuide/Transforms/Transforms.html

Open-source (read 2026-10-23, `main`/`develop` branches):
- [R1] https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityElement.swift (setFrame, setImmediateFrame, isResizable, getWindowId, setMessagingTimeout, EnhancedUI)
- [R2] https://github.com/rxhanson/Rectangle/blob/main/Rectangle/Utilities/CGExtension.swift (`screenFlipped`)
- [R3] https://github.com/rxhanson/Rectangle/blob/main/Rectangle/Rectangle-Bridging-Header.h (`_AXUIElementGetWindow`)
- [R4] https://github.com/rxhanson/Rectangle/blob/main/Rectangle/Utilities/AXExtension.swift ; .../AccessibilityAuthorization/AccessibilityAuthorization.swift (0.3 s poll)
- [RD1] https://github.com/rxhanson/Rectangle/blob/main/TerminalCommands.md (`enhancedUI` modes 1-4)
- [RI1] https://github.com/rxhanson/Rectangle/issues/912 (Chrome slow reposition/resize)
- [RS1] https://github.com/rxhanson/Rectangle/blob/main/Rectangle/Snapping/SnappingManager.swift (NSEvent mouse monitors)
- [A1] https://github.com/nikitabobko/AeroSpace/blob/main/Sources/AppBundle/tree/MacApp.swift (`setAxFrame`, `disableAnimations`)
- [A2] https://github.com/nikitabobko/AeroSpace/blob/main/Sources/AppBundle/model/AxUiElementWindowType.swift (`isDialogHeuristic`)
- [A3] https://github.com/nikitabobko/AeroSpace/blob/main/Sources/PrivateApi/include/private.h
- [A4] same MacApp.swift lines ~69, ~377-379 (observed notifications)
- [A5] https://github.com/nikitabobko/AeroSpace/blob/main/Sources/AppBundle/util/AxSubscription.swift (AXObserver wrapper, per-app thread token)
- [L1] https://github.com/MrKai77/Loop/blob/develop/Loop/Extensions/AXUIElement%2BExtensions.swift (settable check, `AXEnhancedUserInterface`, `AXFullScreen`, window id)
- [LD1] https://github.com/MrKai77/Loop/blob/develop/Loop/Core/WindowDragManager.swift (drag via event monitors + frame polling)
- [P1] https://github.com/kasper/phoenix/pull/310 (disable EUI during move; Chrome symptom; closed, not reproducible)

Not covered: yabai (uses private SkyLight/SA injection for most window ops, so little public-AX content); Amethyst (tree listed, source not read).
