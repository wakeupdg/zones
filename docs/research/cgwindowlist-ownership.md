# CGWindowList and window ownership

Research for Zones (Swift 6, macOS 14+, no private APIs). Researched 2026-10-23 on macOS 27.0.1.
Tags like [S3] point to `## Sources`. "Probe" = my local run of a throwaway Swift tool (see Gotchas, last item).

## Findings

1. **Enumerate on-screen windows.** Call `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`.
   - `optionOnScreenOnly` lists on-screen windows front to back and wants `kCGNullWindowID` [S2]. `excludeDesktopElements` drops the wallpaper and desktop icons [S3].
   - It returns NULL outside a GUI session; it is "relatively expensive" per Apple, so profile it [S1][S20].
   - All four WMs use this exact call (Rectangle [S30], Loop [S33], AeroSpace [S36], Amethyst [S39]).
2. **Filter to "normal" windows.** Keep an entry only if all hold:
   - `kCGWindowLayer == 0`. Layer is an int [S5]. Level constants: Normal 0, Floating 3, Dock 20, MainMenu 24, Status 25 [S21]. Amethyst and AeroSpace use `== 0` [S38][S36].
   - `kCGWindowAlpha > 0.01`. Alpha runs 0.0 to 1.0 [S7]. Loop uses `> 0.01` [S34].
   - `kCGWindowIsOnscreen == true` (a CFBoolean [S8]). Loop checks it [S35].
   - Loop's variant: `0 <= level < kCGMainMenuWindowLevel` [S34]. Rectangle's: `level < 21` and `alpha > 0` [S31].
   - Minimum size is not specified by any source. It is a Zones policy choice (e.g. reject w or h below ~50 pt). Amethyst exposes min width and height as user prefs [S38].
   - Layer 0 can still include Stage Manager strips and Dock-owned windows. Rectangle also skips owner names "Dock", "WindowManager", "Notification Center" [S31][S32].
3. **Per-display assignment.** There is no per-display query; the window server reports one global space.
   - `kCGWindowBounds` is a CGRect dictionary in screen space, origin top-left of the main display; decode with `CGRect(dictionaryRepresentation:)` [S6].
   - `CGDisplayBounds` uses the same global top-left space [S22], so intersect or test the center point.
   - NSScreen frames are bottom-left origin. Flip once at the boundary (Rectangle's `screenFlipped`, used in [S31][S32]).
4. **AXUIElement to CGWindowID without `_AXUIElementGetWindow`.**
   - Rectangle, Loop and AeroSpace all declare the private symbol [S23][S37][S29]. Zones may not.
   - Public fallback = match by `pid` + exact frame. Rectangle: first `WindowInfo` with `pid == pid && frame == frame`; its comment says "no real way to guarantee which window we're actually getting" [S31].
   - Amethyst matches `kCGWindowOwnerPID` then `frame.equalTo(window.frame())`; if several still match it applies a further tie-break [S40].
   - Loop compares AX `position`/`size` with CG bounds for equality, then confirms by ID using the private call [S34].
   - AX supplies position and size (`kAXPositionAttribute`, `kAXSizeAttribute`); both sides are top-left global points, so compare with a tolerance of about 1 pt.
5. **Where title matching fails.**
   - `kCGWindowName` is withheld without Screen Recording (see 8). AX `kAXTitleAttribute` is available with Accessibility permission, but only the CG side is gated, so you cannot compare titles unless the user grants Screen Recording.
   - Apple notes "few applications set the Quartz window name" [S9], so even with permission the name is often empty.
   - Identical frames (cascaded or tabbed windows, two maximized windows) make pid+frame ambiguous. Break ties with z-order (CG list order vs AX order), never by "first match" alone.
6. **CGWindowID lifetime.**
   - Apple: the window ID is "unique within the current user session" [S4]. Header: "unique value within the user session" [S21].
   - Rectangle states real IDs "are assigned incrementally by the window server" [S31]. That implies no reuse within a session, but no Apple text promises it. Treat it as unverified.
   - Across Spaces: no Apple statement. `optionAll` includes off-screen windows [S10] (probe: 249 entries vs 22 on-screen). Whether IDs survive a Space switch is therefore inferred, not documented. Verify in a spike.
   - An ID can die at any time. `CGWindowListCreateDescriptionFromArray` silently drops vanished IDs, so match by `kCGWindowNumber`, not array index [S11].
7. **Permissions matrix (macOS 14/15, what the sources support).**
   - Free: `kCGWindowNumber`, `OwnerPID`, `Layer`, `Bounds`, `Alpha`, `IsOnscreen`. Apple's key docs list no gate on them [S4][S5][S6][S7][S8].
   - Gated: `kCGWindowName`. Apple DTS: values are "modified by the Screen Recording privilege", the call still succeeds, you just lose "potentially private values like `kCGWindowName`" [S13]; also "gated by the Screen Recording user data protection" [S12].
   - Apple's own `kCGWindowName` doc page says nothing about the gate [S9]; the forum posts are the primary evidence.
   - `kCGWindowOwnerName`: a forum report says it is nil without permission on macOS 26 but populated on a macOS 27 beta [S14]. Unverified (thread not loadable here). Do not depend on it; use `NSRunningApplication(processIdentifier:)` (Rectangle does [S31]).
   - Preflight with `CGPreflightScreenCaptureAccess()` [S15]. Chromium uses it on macOS 11+ and a named-window heuristic on 10.15 [S16].
   - Sequoia (15) re-prompts for Screen Recording monthly, ScreenCaptureKit included (beta-era press reports) [S25].
8. **Detect that a window moved.** Two options; combine them.
   - Polling: probe on macOS 27.0.1, Screen Recording granted: 0.41 ms/call for 22 on-screen windows, 1.67 ms/call with `optionAll` (249 windows), 100-call average. Rectangle caches the list for 100 ms [S30].
   - For one window, don't enumerate: `CGWindowListCreateDescriptionFromArray([id])` or `.optionIncludingWindow` with the ID [S11][S30]. Rectangle's `getWindowFrame` does this because drag tracking "needs current geometry" [S30].
   - AX observer: `kAXMovedNotification` / `kAXResizedNotification` per window [S26][S27]. AeroSpace subscribes moved + resized + destroyed + (de)miniaturized on each window [S36].
   - AeroSpace still re-checks on mouse-up because "kAXUIElementDestroyedNotification is that unreliable" [S36].
   - Whether Moved notifications stream continuously during a drag is untested here; spike before relying on it.
9. **Which window is the user dragging at mouse-down.** Preferred order:
   - (a) Public CGEvent field `kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent` returns the window ID under the pointer [S24]. Rectangle reads it on `.leftMouseDown` [S28]. Doc is header-only (the Apple web page has no text).
   - (b) CG hit-test: list is front to back [S2], so take the first layer-0, alpha > 0, on-screen entry whose bounds contain the point. Rectangle [S31] and Amethyst (`topWindowForScreenAtPoint`) [S40] do this.
   - (c) `AXUIElementCopyElementAtPosition(systemWide, x, y)` hit-tests by z-order, topmost wins [S19]. Loop falls back to it [S33].
   - Convert the AppKit mouse point to top-left global coordinates before comparing with CG bounds.
10. **Ownership: own app vs others.**
    - Exclude Zones by `kCGWindowOwnerPID == getpid()` (primary). `NSRunningApplication.processIdentifier` is the pid, -1 if none [S17].
    - Secondary: skip IDs in `NSApp.windows.map { CGWindowID($0.windowNumber) }`. Rectangle excludes its click-through preview windows this way [S31][S32]. `NSApplication.windows` includes off-screen windows on all Spaces, unordered [S18].
    - Apple says `NSWindow.windowNumber` "isn't the same as the global window number assigned by the window server" [S3a]. In my probe on macOS 27.0.1 it matched exactly: `windowNumber` 23654/23655 appeared as `kCGWindowNumber` 23654/23655. Rectangle casts it directly [S32]. Keep pid as the contract; use windowNumber as belt and braces.
11. **ScreenCaptureKit alternative.**
    - `SCShareableContent.getExcludingDesktopWindows(_:onScreenWindowsOnly:)` (macOS 12.3+) returns `SCWindow`s [S41][S42]. `SCWindow` exposes `windowID` ("The Core Graphics window identifier"), `isOnScreen`, `windowLayer`, `owningApplication` [S43].
    - Cost: async, and any `SCShareableContent` call triggers the Screen Recording prompt, even if you want only metadata (Apple DTS thread context) [S44]. It adds permission cost with no benefit over CGWindowList for bounds/pid/layer.
    - Conclusion: do not use it for Zones.

## Gotchas

- **`optionIncludingWindow` alone.** Apple says to combine it with another option for "meaningful results" [S45], yet Rectangle and Loop call it alone with an ID and rely on it [S30][S34]. Test on 14 and 15 before depending on it.
- **Do not trust `OwnerName`/`Name` for logic.** Gated or unreliable (finding 7). Rectangle's "Dock"/"WindowManager" exclusion rides on owner names [S31]. Prefer bundle id from `NSRunningApplication`.
- **Coordinates.** CG and AX are top-left global; AppKit is bottom-left. Mixed-DPI and display arrangement change which display's `maxY` you flip around.
- **Frame equality is fragile.** A window mid-animation or at fractional positions fails exact match; use a tolerance. Rectangle's last resort when nothing matches is a synthetic ID from `CFHash(element)` with the high bit set [S31].
- **AX coverage gaps.** An Apple Forums poster found full-screen windows missing from `kAXWindowsAttribute`/children of a fresh app element, while retained handles stayed valid [S46]. Other Spaces: unverified.
- **AX writes lie.** A success return from an AX set does not prove the window moved (full-screen, sheets, busy apps) [S47]. Always re-read the frame.
- **Own overlay at layer 3.** A `.floating` panel appears at layer 3. AeroSpace treats 3 as "alwaysOnTop" [S36]; pid exclusion is required, a layer filter is not enough. Probe confirmed own panel at layer 3, alpha 1.
- **Cursor window.** Probe showed layer 2147483630 entries (6 on this host), which are cursor-level; `layer == 0` drops them [S21].
- **Probe limits.** The probe process already had Screen Recording (`CGPreflightScreenCaptureAccess() == true`), so the denied case (nil names, empty `kCGWindowName`) was NOT reproduced. Timings are from one machine. Probe source: `/private/tmp/claude-501/-Users-dganesh--MY-PROJECTS-open-source-clones-fancy-zones/faae5a4c-2276-4507-97e4-667cc6d49ef2/scratchpad/cgprobe.swift` (session-temp, not in repo).
- **Source snapshot.** WM code was read from HEAD tarballs on 2026-10-23; line numbers drift.

## Implications for Zones

1. Window model = `(windowID, pid, bounds, layer)` from CGWindowList; never require `kCGWindowName` or `kCGWindowOwnerName`. Zones needs no Screen Recording permission, only Accessibility (for AX moves/resizes and the global mouse event tap).
2. Enumeration helper: `onScreenNormalWindows()` = finding 1 + 2, minus own pid, minus Dock/WindowManager/Notification Center bundles; ~0.4 ms, so call at drag start, not per frame.
3. Drag start: read the CGEvent window-under-pointer field first, fall back to front-to-back hit-test, then map to an AXUIElement by pid + frame (tolerance ~1 pt, tie-break by z-order). Fail closed (no snap) if still ambiguous.
4. During the drag, track only the dragged window: poll `CGWindowListCreateDescriptionFromArray([id])` on each mouse-dragged event or display tick; no full enumeration.
5. Out-of-drag changes (user moves/closes a snapped window): AX observers (moved, resized, destroyed) plus a low-rate resync (about 1 Hz while any zoned window exists) as a safety net, mirroring AeroSpace's mouse-up recheck.
6. Own overlays: `NSPanel`s with `ignoresMouseEvents = true`; excluded by pid, with `windowNumber` set as a secondary filter. Keep overlay level above `.normal` but accept layer-3 collisions.
7. Treat CGWindowID as an in-session key only, never persist it. Persist layouts by bundle id + zone, not by window ID.
8. Spikes needed before the build run: (a) windowNumber == CGWindowID on macOS 14 and 15, (b) AX moved notifications during a live drag, (c) ID stability across Spaces and full-screen, (d) behavior with Screen Recording denied (nil/empty names), (e) `optionIncludingWindow` alone on 14/15.

## Sources

Apple docs (JSON endpoints of developer.apple.com, fetched 2026-10-23):
- [S1] https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)
- [S2] https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/optiononscreenonly
- [S3] https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/excludedesktopelements
- [S3a] https://developer.apple.com/documentation/appkit/nswindow/windownumber
- [S4] https://developer.apple.com/documentation/coregraphics/kcgwindownumber
- [S5] https://developer.apple.com/documentation/coregraphics/kcgwindowlayer
- [S6] https://developer.apple.com/documentation/coregraphics/kcgwindowbounds
- [S7] https://developer.apple.com/documentation/coregraphics/kcgwindowalpha
- [S8] https://developer.apple.com/documentation/coregraphics/kcgwindowisonscreen
- [S9] https://developer.apple.com/documentation/coregraphics/kcgwindowname
- [S10] https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/optionall
- [S11] https://developer.apple.com/documentation/coregraphics/cgwindowlistcreatedescriptionfromarray(_:)
- [S15] https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()
- [S17] https://developer.apple.com/documentation/appkit/nsrunningapplication/processidentifier
- [S18] https://developer.apple.com/documentation/appkit/nsapplication/windows
- [S19] https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition
- [S20] https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:) (same page as S1; the "relatively expensive" sentence)
- [S22] https://developer.apple.com/documentation/coregraphics/cgdisplaybounds(_:)
- [S26] https://developer.apple.com/documentation/applicationservices/kaxmovednotification
- [S27] https://developer.apple.com/documentation/applicationservices/kaxresizednotification
- [S41] https://developer.apple.com/documentation/screencapturekit/scshareablecontent
- [S42] https://developer.apple.com/documentation/screencapturekit/scshareablecontent/getexcludingdesktopwindows(_:onscreenwindowsonly:completionhandler:)
- [S43] https://developer.apple.com/documentation/screencapturekit/scwindow/windowid (also `/isonscreen`, `/windowlayer`, `/owningapplication`)
- [S45] https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/optionincludingwindow
- [S16r] CGRequestScreenCaptureAccess: https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess()

Local SDK headers (Xcode CLT, `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/CoreGraphics.framework/Headers/`):
- [S21] `CGWindow.h` (key comments, "unique value within the user session", NULL outside GUI session) and `CGWindowLevel.h` (level constants)
- [S24] `CGEventTypes.h` lines 377-378 (`kCGMouseEventWindowUnderMousePointer[ThatCanHandleThisEvent]`)

Apple forums / third party (note: some forum pages block automated fetch; those claims are from search excerpts and flagged above):
- [S12] https://developer.apple.com/forums/thread/126860 (Quinn: name "gated by the Screen Recording user data protection"; fetched)
- [S13] https://developer.apple.com/forums/thread/706187 (Quinn: privilege changes values, not success; fetched)
- [S14] https://developer.apple.com/forums/thread/839069 (owner name nil on 26 / populated on 27 beta; search excerpt only)
- [S44] https://developer.apple.com/forums/thread/849969 (SCShareableContent triggers prompt; wallpaper capture on 27; fetched)
- [S46] https://developer.apple.com/forums/thread/121114 (full-screen windows missing from AX windows; search excerpt)
- [S47] https://pkg.go.dev/github.com/go-macos/accessibility (AX set returns success without moving; search excerpt)
- [S16] https://chromium.googlesource.com/chromium/src/+/d4afc97b7/ui/base/cocoa/permissions_utils.mm
- [S25] https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/ (and https://tidbits.com/2024/08/19/apple-reduces-excessive-sequoia-permission-requests-shifts-to-monthly); beta-era, final behavior not re-verified

Open-source WMs (GitHub, HEAD as of 2026-10-23):
- [S28] https://github.com/rxhanson/Rectangle/blob/HEAD/Rectangle/Rectangle/Snapping/SnappingManager.swift (`.leftMouseDown`, window-under-pointer field)
- [S30] https://github.com/rxhanson/Rectangle/blob/HEAD/Rectangle/Rectangle/Utilities/WindowUtil.swift (100 ms cache, `getWindowFrame`, option sets)
- [S31] https://github.com/rxhanson/Rectangle/blob/HEAD/Rectangle/Rectangle/AccessibilityElement.swift (pid+frame fallback, hit test, exclusions, derived ID)
- [S32] https://github.com/rxhanson/Rectangle/blob/HEAD/Rectangle/Rectangle/Utilities/OverlapOffsetGeometry.swift (own-window exclusion by `windowNumber`)
- [S23] https://github.com/rxhanson/Rectangle/blob/HEAD/Rectangle/Rectangle/Rectangle-Bridging-Header.h (private `_AXUIElementGetWindow`)
- [S33] https://github.com/MrKai77/Loop/blob/HEAD/Loop/Loop/Window%20Management/Window/WindowUtility.swift
- [S34] https://github.com/MrKai77/Loop/blob/HEAD/Loop/Loop/Window%20Management/Window/Window.swift (alpha/level filters, frame match, `isWindowHidden`)
- [S37] https://github.com/MrKai77/Loop/blob/HEAD/Loop/Loop/Private%20APIs/PrivateApis.swift
- [S29] https://github.com/nikitabobko/AeroSpace/blob/HEAD/Sources/PrivateApi/include/private.h
- [S36] https://github.com/nikitabobko/AeroSpace/blob/HEAD/Sources/AppBundle/windowLevelCache.swift , `tree/MacApp.swift` (AX notifications), `GlobalObserver.swift` (mouse-up recheck)
- [S35] same as S34 (`isWindowHidden`)
- [S38] https://github.com/ianyh/Amethyst/blob/HEAD/Amethyst/Amethyst/Preferences/UserConfiguration.swift
- [S39] https://github.com/ianyh/Amethyst/blob/HEAD/Amethyst/Amethyst/Model/CGInfo.swift
- [S40] https://github.com/ianyh/Amethyst/blob/HEAD/Amethyst/Amethyst/Model/WindowsInformation.swift
- Local measurements: probe described in Gotchas (macOS 27.0.1, one machine, Screen Recording granted).
