# NSPanel overlay levels over full-screen apps

Scope: translucent zone rectangles on every display while a window is dragged with Shift held, including over full-screen and Split View Spaces, without taking focus or breaking the drag. Researched 2026-10-23. Tags: **[Apple]** = Apple primary doc, **[DTS]** = Apple engineer forum answer, **[OSS]** = read in source, **[Measured]** = run locally on macOS 27.0.1 (26A434), **[Unverified]** = no primary source found, needs a spike.

## Findings

1. **Level numbers (measured).** `NSWindow.Level` is ordered low to high and "the stacking of levels takes precedence over the stacking of windows within each level" [S1]. Apple does not publish the numbers [S1][S14]. Measured with `NSWindow.Level` / `CGWindowLevelForKey` [S15]:
   - normal 0, floating 3, modalPanel 8, mainMenu 24, statusBar 25, popUpMenu 101, **screenSaver 1000**.
   - CG keys: overlayWindow 102, draggingWindow 500, assistiveTechHighWindow 1500, cursorWindow 2147483630, maximumWindow 2147483631.
   - A 2020 blog lists `NSWindow.Level.screenSaver` as 101 [S34]. That is wrong on macOS 27 (measured 1000). Apple DTS also says 1000 [S12]. Never hardcode numbers.
2. **What shows over another app's full-screen Space (DTS).** Apple DTS answered exactly this question [S12]:
   - `.floating` (3) and `.statusBar` (25) do not show over full-screen content; `.screenSaver` (1000) does.
   - `collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]`. Setting only these on a plain `NSWindow` at `.floating`/`.statusBar` still failed.
   - The window must be an `NSPanel` with `.nonactivatingPanel`. Ordering a regular `NSWindow` front activates the app and "can cause a full-screen app to exit its Space".
   - The app must use the accessory activation policy (`LSUIElement` = 1 is equivalent [S35]); regular foreground apps cannot layer above other apps' full-screen Spaces.
   - DTS tested macOS 26 with full-screen Safari, QuickTime Player and full-screen YouTube; the panel stayed on top. Split View was not tested [S12].
3. **Collection behavior meanings [S2][S3].**
   - `.canJoinAllSpaces`: can appear in all spaces. `.fullScreenAuxiliary`: displays on the same space as the full-screen window.
   - `.stationary`: Mission Control does not affect it. `.ignoresCycle`: not in Cycle Through Windows. `.transient`: floats in Spaces, hides in Mission Control.
   - `.canJoinAllApplications` (macOS 13+): skips Stage Manager layout, can join other apps' full-screen Spaces; "use for floating windows and system overlays" [S3].
   - Caveat: [S3] says `primary`, `auxiliary`, `canJoinAllApplications` are mutually exclusive "on a window handled by Stage Manager". DTS's working config sets `.fullScreenAuxiliary` and `.canJoinAllApplications` together [S12]. Keep both, re-test.
4. **Panel flags.**
   - Panels default to `hidesOnDeactivate = true` (windows: false) [S7]. Set it to false: our app is never active during a drag.
   - `isFloatingPanel` is for small mouse-oriented panels that do not become key [S5]; DTS sets it true [S12]. It does not replace the level choice.
   - `becomesKeyOnlyIfNeeded`: a non-activating panel becomes key only if the hit view returns true from `needsPanelToBecomeKey` [S6]. A click-through panel has no hit view, so it never becomes key.
   - `.borderless` = "none of the usual peripheral elements" [S8]. `canBecomeKey` is true only if the style mask includes `.titled` [S9], so a borderless panel cannot become key by default. Override `canBecomeKey`/`canBecomeMain` to false anyway as a guard.
   - `orderFrontRegardless()` "moves the window to the front of its level, even if its application isn't active, without changing either the key window or the main window" [S10]. Use it, never `makeKeyAndOrderFront`.
5. **Transparency and click-through.** `ignoresMouseEvents = true` makes the window "transparent to mouse events" [S11]. Add `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false` [S27][S29]. Rectangle also sets `animationBehavior = .none`, `isReleasedWhenClosed = false`, `colorSpace = .sRGB` [S27].
6. **Reference overlays (OSS, read in source).**
   - Loop: `NSPanel` subclass, `[.borderless, .nonactivatingPanel]`, `ignoresMouseEvents = true`, `collectionBehavior = .canJoinAllSpaces`, `level = screenSaver - 1` (999), `NSHostingView` content, `setFrame(screen.frame)`, `orderFrontRegardless()`. It is created once and reused; on a screen change it only calls `setFrame` [S29]. The subclass overrides `hasKeyAppearance`/`hasActiveAppearance` to true so the panel never looks inactive [S30].
   - Rectangle: borderless `NSWindow` (not a panel), `level = .modalPanel`, `collectionBehavior = [.transient, .ignoresCycle]`, `ignoresMouseEvents = true`. One window is reused for the whole drag; it is sized to the target screen's frame plus 96 pt shadow padding and the visible rect is moved inside it by layers [S27]. It is driven from a global `NSEvent` monitor on `leftMouseDragged` [S28]. Its flags have no `.fullScreenAuxiliary`/`.canJoinAllSpaces`, so by [S2] it is not set up for full-screen Spaces.
   - AeroSpace/yabai: no primary doc found on overlay levels. yabai's layer and sticky features need a scripting addition injected into Dock.app with partial SIP disabled [S36, secondary]. Not an option for Zones (no private APIs).
7. **Screens and Spaces.**
   - `NSScreen.frame` is the full rectangle "including any space occupied by the menu bar and dock" [S16]. `visibleFrame` excludes dock, menu bar, and on notched Macs "the bezel or the visible areas on either side of the bezel" [S17]. Do not cache it [S17].
   - "Displays have separate Spaces" is a user setting exposed as `NSScreen.screensHaveSeparateSpaces` [S19]. Each display can therefore be in a different Space (one full-screen, one normal), which is why one panel per display is needed.
   - `safeAreaInsets` (macOS 12+) gives the unobscured area; `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` give the areas beside the camera housing [S17][S18].
   - `constrainFrameRect(_:to:)` runs automatically for titled windows [S20]. A borderless panel is not constrained, but Rectangle overrides it too [S27].
   - Rectangle comment: a zero-sized frame on a shared edge "can attach to the neighboring display's Space"; keep the first visible pixel inside the destination [S27].
8. **Drag is not interrupted (evidence is indirect).** No Apple doc speaks to showing a window mid-drag. Evidence: `orderFrontRegardless` leaves key/main unchanged [S10]; `ignoresMouseEvents` makes the window transparent to mouse events [S11]; Rectangle shows its window while a window drag is in progress, from a `leftMouseDragged` monitor [S28]. Loop shows the same kind of click-through panel while its trigger is held, not specifically during a drag [S29]. Needs a spike on a full-screen Space (see Implications).
9. **Redraw.**
   - `maximumFramesPerSecond` (macOS 12+) gives the refresh rate [S22]. `NSView.displayLink(target:selector:)` (macOS 14+) is "in-sync with the display the view is on" and is not invoked when the view is hidden or off-screen [S21].
   - Rectangle updates `CALayer` geometry from a `Timer` at `max(60, maximumFramesPerSecond)` inside a `CATransaction` with `setDisableActions(true)` and `CATransaction.flush()` [S27][S25].
   - `drawsAsynchronously` defaults to false; Apple says to "always measure" before enabling [S23].
   - `contentsScale`: set by the view for view-attached layers; for layers you create yourself you must set it from the screen [S24]. Rectangle sets `contentsScale = screen.backingScaleFactor` [S27].
   - `NSHostingView` is the AppKit host for SwiftUI; `sizingOptions` controls the constraints it creates from SwiftUI content size [S26].
10. **Accessibility.**
   - `isAccessibilityElement` controls whether an element "participates in the accessibility hierarchy" [S31]; SwiftUI has `.accessibilityHidden(_:)` [S32].
   - `NSWorkspace.accessibilityDisplayShouldReduceMotion`: avoid large animations when true; observe `accessibilityDisplayOptionsDidChangeNotification` [S33]. Rectangle also reads `accessibilityDisplayShouldReduceTransparency` and drops blur/fades [S27].

## Gotchas

- Wrong level numbers circulate [S34]; measured screenSaver = 1000 [S15]. `maximumWindow` (2147483631) and `cursorWindow` are above everything; a 2002/2009-era Apple guide discourages custom levels [S13] and DTS says `.screenSaver` is enough [S12]. Use `.screenSaver`, not `+1`.
- A regular `NSWindow`, or a non-accessory app, fails over full-screen Spaces even with the right flags [S12]. Ship as `LSUIElement`/`.accessory`.
- Menu bar is level 24 [S15]. A level-1000 panel with `frame = screen.frame` covers the menu bar and the notch strip; it is click-through so nothing is blocked.
- `visibleFrame` can be smaller than the screen even when the Dock auto-hides [S17]. Do not treat `frame - visibleFrame` as "Dock height".
- Layer ordering is per level only [S1][S13]. Our panel sits above all other app windows, so zone rectangles also draw over the dragged window itself; keep fills translucent.
- Rectangle orders its window just below a specific window ID at that window's level when blur is on [S27]; that trick keeps the dragged window above the footprint but would hide the overlay in other cases. Not needed for Zones.
- `CALayer` property changes animate implicitly (~0.25 s) unless actions are disabled [S25].
- Our own overlay appears in `CGWindowListCopyWindowInfo` at layer 1000; filter our own PID when hit-testing windows under the cursor (reasoning from [S27], which reads `kCGWindowLayer`; not otherwise sourced).
- [Unverified] `canJoinAllSpaces` may not cover Spaces created after launch (single forum report, snippet only) [S37]. Re-assert `orderFrontRegardless()` from `NSWorkspace.activeSpaceDidChangeNotification` only if the spike shows it.
- [Unverified] Behavior on Split View Spaces, on a full-screen Space whose menu bar auto-hides (what `visibleFrame` reports), and on macOS 27 specifically.
- [Unverified] Whether `NSWindow.sharingType` matters here. Apple documents only that it sets "the level of access other processes have to the window's content" [S38]. Leave at default.

## Implications for Zones

1. **Panel recipe (one per `NSScreen`).**
   - `final class ZoneOverlayPanel: NSPanel`, `styleMask: [.borderless, .nonactivatingPanel]`, `backing: .buffered`, `defer: false`.
   - `level = .screenSaver`; `collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.
   - `isFloatingPanel = true`, `hidesOnDeactivate = false`, `becomesKeyOnlyIfNeeded = true`, `ignoresMouseEvents = true`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `animationBehavior = .none`, `isReleasedWhenClosed = false`.
   - Override `canBecomeKey` and `canBecomeMain` to false. App: `NSApp.setActivationPolicy(.accessory)` / `LSUIElement`.
   - Show with `orderFrontRegardless()` once per drag session; hide with `orderOut(nil)`. Never call `makeKey*`, `NSApp.activate`, or `orderFront` per mouse move.
2. **Sizing.** `setFrame(screen.frame, display: false)`. Compute zone rects from the layout in `visibleFrame` coordinates (that is where snapped windows land) and convert to panel-local coordinates; read `visibleFrame` fresh each drag [S17]. The panel covers menu bar and notch but zones never draw there. Rebuild panels on screen add/remove/resolution change; keep them otherwise.
3. **Lifecycle.** Create panels when the Shift-drag session starts (or pre-create and keep ordered out), reuse them, update model only. Mirror Loop: no re-creation per frame [S29]. Keep frames non-empty and on-screen [S27].
4. **Rendering.** Root view layer-backed (`wantsLayer = true`), one `CALayer` per zone plus one highlight layer. Move the highlight by setting layer `frame`/`opacity` inside `CATransaction.setDisableActions(true)` (or a short explicit animation); no `draw(_:)` on the hot path, so `drawsAsynchronously` stays off [S23]. Use `view.displayLink` (macOS 14+) only if something needs per-frame work [S21]. Set `contentsScale` for any standalone layer [S24]. SwiftUI via `NSHostingView` is acceptable for static zone chrome (Loop does it [S29]) but is [Unverified] at 120 Hz; benchmark before choosing.
5. **Accessibility.** Mark the hosting view and layers `isAccessibilityElement = false`, SwiftUI content `.accessibilityHidden(true)` [S31][S32]. Honor reduce motion and reduce transparency (no fades/blur, solid fill) [S33][S27]. The overlay is a visual aid only; zone choice must also work without seeing it (e.g. a keyboard/menu path).
6. **Spike before building features (all Unverified items).** On macOS 14 and macOS 27: (a) drag a Finder/Safari window with Shift held onto a display showing a full-screen app and onto a Split View Space; panel must be visible and drag uninterrupted; (b) confirm frontmost app and key window never change (log `NSWorkspace.frontmostApplication`, `NSApp.keyWindow`); (c) full-screen Space with menu bar auto-hidden: log `frame` vs `visibleFrame`; (d) create a new Space after launch and re-test; (e) read the panel in Accessibility Inspector and VoiceOver; (f) Instruments frame pacing on a 120 Hz display; (g) compare with and without `.canJoinAllApplications`.

## Sources

Apple docs (developer.apple.com/documentation/...):
- [S1] NSWindow.Level: https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct
- [S2] NSWindow.CollectionBehavior: https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct
- [S3] canJoinAllApplications: https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications
- [S4] NSPanel: https://developer.apple.com/documentation/appkit/nspanel
- [S5] isFloatingPanel: https://developer.apple.com/documentation/appkit/nspanel/isfloatingpanel
- [S6] becomesKeyOnlyIfNeeded: https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded
- [S7] hidesOnDeactivate: https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate
- [S8] NSWindow.StyleMask: https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct
- [S9] canBecomeKey: https://developer.apple.com/documentation/appkit/nswindow/canbecomekey
- [S10] orderFrontRegardless(): https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless()
- [S11] ignoresMouseEvents: https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents
- [S13] Window Layers and Levels (archived guide): https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/WinPanel/Concepts/WindowLevel.html
- [S14] CGWindowLevelKey / CGWindowLevelForKey (no numbers; "not recommended for use in applications"): https://developer.apple.com/documentation/coregraphics/cgwindowlevelkey
- [S16] NSScreen.frame: https://developer.apple.com/documentation/appkit/nsscreen/frame
- [S17] NSScreen.visibleFrame: https://developer.apple.com/documentation/appkit/nsscreen/visibleframe
- [S18] NSScreen.safeAreaInsets: https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets
- [S19] screensHaveSeparateSpaces: https://developer.apple.com/documentation/appkit/nsscreen/screenshaveseparatespaces
- [S20] constrainFrameRect(_:to:): https://developer.apple.com/documentation/appkit/nswindow/constrainframerect(_:to:)
- [S21] NSView.displayLink(target:selector:): https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:)
- [S22] maximumFramesPerSecond: https://developer.apple.com/documentation/appkit/nsscreen/maximumframespersecond
- [S23] CALayer.drawsAsynchronously: https://developer.apple.com/documentation/quartzcore/calayer/drawsasynchronously
- [S24] CALayer.contentsScale: https://developer.apple.com/documentation/quartzcore/calayer/contentsscale
- [S25] CATransaction.setDisableActions: https://developer.apple.com/documentation/quartzcore/catransaction/setdisableactions(_:)
- [S26] NSHostingView: https://developer.apple.com/documentation/swiftui/nshostingview
- [S31] isAccessibilityElement(): https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol/isaccessibilityelement()
- [S32] accessibilityHidden(_:): https://developer.apple.com/documentation/swiftui/view/accessibilityhidden(_:)
- [S33] accessibilityDisplayShouldReduceMotion: https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion
- [S35] ActivationPolicy.accessory: https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory
- [S38] NSWindow.sharingType: https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.property

Apple DTS / forums:
- [S12] "Overlay window above all windows, even when moving spaces" (DTS accepted answer): https://developer.apple.com/forums/thread/826308
- [S37] "Make NSWindow show up on every workspace, even newly created ones after" (search snippet only, not opened): https://developer.apple.com/forums/thread/671674

Open source (commit-pinned):
- [S27] Rectangle FootprintWindow.swift: https://github.com/rxhanson/Rectangle/blob/7c5c9c56b447dad4e3720b805e54b1d115b1a90e/Rectangle/Snapping/FootprintWindow.swift
- [S28] Rectangle SnappingManager.swift (same commit): https://github.com/rxhanson/Rectangle/blob/7c5c9c56b447dad4e3720b805e54b1d115b1a90e/Rectangle/Snapping/SnappingManager.swift
- [S29] Loop PreviewController.swift: https://github.com/MrKai77/Loop/blob/573ace3071641bbe002527ccfc0811842300ccba/Loop/Window%20Action%20Indicators/Preview%20Window/PreviewController.swift
- [S30] Loop ActivePanel.swift: https://github.com/MrKai77/Loop/blob/573ace3071641bbe002527ccfc0811842300ccba/Loop/Window%20Action%20Indicators/ActivePanel.swift

Other:
- [S15] Local measurement: Swift script printing `NSWindow.Level.*.rawValue` and `CGWindowLevelForKey(...)` on macOS 27.0.1 (26A434).
- [S34] James Fisher, "What is the order of NSWindow levels?" (community, partly wrong on screenSaver): https://jameshfisher.com/2020/08/03/what-is-the-order-of-nswindow-levels/
- [S36] yabai architecture (DeepWiki, secondary): https://deepwiki.com/asmvik/yabai
