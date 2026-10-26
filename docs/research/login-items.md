# SMAppService login items (launch at login)

Research for Zones (macOS 14+, Swift 6, LSUIElement menu-bar app, no private APIs). Researched 2026-10-23 (the macOS 27.0.1 SDK headers on this Mac were read directly). Items marked UNVERIFIED were not confirmed by a primary source.

## Findings

1. **API calls.** `SMAppService.mainApp` is "an app service object that corresponds to the main application as a login item"; call `try register()` / `try unregister()` and read `.status`. Available macOS 13.0+. [S1][S2][S10]
2. **No Info.plist key or entitlement is needed for `mainApp`.** Apple's docs list no plist keys for it; the bundle-layout rules (`Contents/Library/LoginItems`, `LaunchAgents`) apply only to helper login items, agents and daemons. The one stated requirement is "Apps that use SMAppService APIs must be code signed." [S1][S3][S10]
3. **Apple DTS says no helper bundle is needed.** "You do this straight from your app; there's no indirection required." [S4]
4. **Status cases.** `notRegistered` (never registered, or unregistered); `enabled` (registered and eligible to run); `requiresApproval` (registered, but the user must act in System Settings; also returned "if the user revokes consent"); `notFound` ("an error occurred and no such service could be found"). [S5][S6][S10]
5. **Error codes from `register()`.** `kSMErrorAlreadyRegistered`, `kSMErrorLaunchDeniedByUser` (user has not approved), and `kSMErrorInvalidSignature` ("If the app bundle is not properly code signed"). Numeric values: InternalFailure=2, InvalidSignature=3, AuthorizationFailure=4, ToolNotValid=5, JobNotFound=6, ServiceUnavailable=7, JobPlistNotFound=8, JobMustBeEnabled=9, InvalidPlist=10, LaunchDeniedByUser=11, AlreadyRegistered=12 (the enum starts at 2 and counts up). Error domain constant `SMAppServiceErrorDomain` is declared in the macOS 15+ header; the forum reports `Code=1 "Operation not permitted"` in this domain. [S10][S11]
6. **`unregister()` on the main app does not quit it.** "It will continue running, but will still be unregistered." Unregistering something already unregistered returns `kSMErrorJobNotFound`. [S10]
7. **`openSystemSettingsLoginItems()`** is a class method that "opens System Settings to the Login Items panel". Apple intends it to be called after you show the user a prompt and they confirm. [S7][S10]
8. **No change notification exists.** The headers and docs expose no observer or delegate. Apple's guidance is to check status "when [apps] are launched" and when handling errors. Third-party practice is to re-read status on `onAppear` and when the window becomes active. [S10][S7][S9]
9. **Registration shows a user-visible notification.** WWDC22: apps "will be allowed to launch at login by default, and users will be notified"; clicking the notification opens the Login Items pane. [S8]
10. **User control.** The pane has "Open at Login" (always launched, user-controlled) and "Allow in the Background" (an allowlist of what may launch). Apple DTS describes the semantic difference. [S8][S12]
11. **Legacy APIs are deprecated.** `SMLoginItemSetEnabled` is marked `__OSX_DEPRECATED(10.6, 13.0, "Please use SMAppService instead")`. `LSSharedFileList` login items (`kLSSharedFileListSessionLoginItems`) are deprecated since 10.11 ("Use a LaunchAgent, XPCService or the ServiceManagement APIs instead"). Neither is needed on macOS 14+. [S10][S13]
12. **Open-source implementations all share one shape.** Rectangle (`LaunchOnLogin.swift`), Loop (`LaunchAtLoginManager.swift`) and sindresorhus `LaunchAtLogin-Modern` (used by Ice and Maccy) compute `isEnabled` as `status == .enabled`, call `register()`/`unregister()` in `do/catch`, and only log failures. None of them handle `.requiresApproval` or show a settings link. The sindresorhus code unregisters first if already enabled, then registers. [S14][S15][S16][S17][S18]
13. **App Store rule.** "Launch at login" must be enabled by a user action; the library readme warns that defaulting it to true gets the app rejected. Apple DTS cites guideline 2.4.5(iii), and recommends the user fully controls the item. [S16][S19]

## Gotchas

1. **`notFound` is ambiguous.** Headers say a user revocation gives `.requiresApproval`. But a forum poster saw `.notFound` after disabling in System Settings, and the Scrawl project reports `.notFound` for a never-registered app installed in `/Applications` (macOS 27.0.1, "no registration record" in BTM). Treat `.notFound` as "off, try `register()`", not as fatal. [S10][S19][S20]
2. **Unsigned or ad-hoc builds.** The header says signing is required and `kSMErrorInvalidSignature` is the documented failure. Community evidence is mixed: one PR reports an ad-hoc signed throwaway bundle registered successfully on macOS 27.0.1; another reports an unsigned build created 100+ duplicate "Login Item Added" entries (status `.notFound` each build, so the app re-registered every time). [S10][S21][S22]
3. **Per-build duplicates and stale Launch Services state.** Apple DTS: "the #1 tip... is to find and delete any build of your app other than the one you're actively developing", and test on a clean machine or a new user account because login items are per-user. Error status 78 (`EX_CONFIG`) after a "successful" register was traced to this on dev machines. [S23][S12]
4. **DerivedData, DMG and translocated paths.** No primary source documents `register()` behavior for these. Community reports say a debug build registered from DerivedData leaves an item pointing into build output. App Translocation and DMG behavior is UNVERIFIED: test a quarantined, DMG-mounted copy before claiming support. The only Apple location statement is that daemon-hosting apps "should" live in `/Applications`. [S10][S21]
5. **App moved after registration.** UNVERIFIED for `mainApp`. Apple documents `BundleProgram` as the mechanism that "allow[s] apps to support a user relocating the app bundle", but that applies to agents and daemons, not the main app. Re-check status and re-register on each launch from the new location. [S10]
6. **Bundle ID stability.** UNVERIFIED by a primary source. System Settings shows items by app/bundle, so keep the bundle ID and signing identity stable across releases to avoid duplicates (inference from S3, S22).
7. **`register()` can throw while the state still changes.** `kSMErrorAlreadyRegistered` is thrown for a double register. The library's unregister-then-register workaround exists for this. [S10][S16]
8. **Async unregister variant.** `unregister(completionHandler:)` exists; the sync `unregister()` is fine for a settings click, but do not call either on a hot path. [S10]
9. **Never auto-register at launch.** Re-registering on launch overrides a user who removed the item and is the pattern Apple DTS calls weird. Register only from a user action. [S19]

## Implications for Zones

1. **Use `SMAppService.mainApp` directly.** No helper target, no entitlement, no Info.plist change, no third-party package. Keep one small `LoginItemService` (MainActor) wrapping register/unregister/status. Do not add `LaunchAtLogin-Modern` (it hides `.requiresApproval`).
2. **Source of truth is `status`, never a stored Bool.** Re-read it in the Settings view `.onAppear` and when the window becomes active (`@Environment(\.appearsActive)` or `NSApplication.didBecomeActiveNotification`). A manual refresh after `register()`/`unregister()` is also required.
3. **Toggle behavior.** Binding get: ON only when `status == .enabled` (never ON for `.requiresApproval`). Set: `register()` when turning on (also for `.notFound`, which is "off"), `unregister()` when turning off; wrap in `do/catch`, re-read status afterward, and surface the error text inline.
4. **Approval UX.** When status is `.requiresApproval` (or `register()` throws `kSMErrorLaunchDeniedByUser`), show the toggle off plus a caption "Zones is turned off in Login Items" and a `Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }`. Refresh again when the app becomes active.
5. **Errors.** Map `kSMErrorInvalidSignature` to "This build isn't properly signed; launch-at-login works in the signed release from /Applications". Disable the toggle only if `SMAppService.mainApp` is unusable; never disable it on `.notFound`.
6. **Off by default.** First launch must not register. Offer it in onboarding or Settings as an explicit opt-in.
7. **LSUIElement at login.** `LSUIElement` only means no Dock icon and no app menu bar; it does not change login behavior. The app is launched on next login and starts straight into its menu-bar item. Detect "launched at login" with the `kAEOpenApplication` event carrying `keyAELaunchedAsLogInItem` (check only inside `applicationDidFinishLaunching`) and skip showing onboarding or Settings windows on that path. Registration only affects future logins; the running app is not relaunched. [S10][S16][S24][S25]
8. **Test plan for the build run.** On a clean user account with a signed `/Applications` copy: off to on, status `enabled`; toggle off in System Settings, status becomes `requiresApproval` or `notFound` (record which on the current macOS); move the app, quarantine it from a DMG, and ad-hoc sign it and note each `register()` result. Reset stale state with `sfltool resetbtm` between runs.
9. **Dev builds.** Do not register from Xcode/DerivedData runs. Gate the toggle with a "Debug build" caption, and delete stray builds so Launch Services has one copy.

## Sources

- [S1] https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp
- [S2] https://developer.apple.com/documentation/servicemanagement/smappservice
- [S3] https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos
- [S4] https://developer.apple.com/forums/thread/777520 (Apple DTS: mainApp register example)
- [S5] https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum
- [S6] https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval
- [S7] https://developer.apple.com/documentation/servicemanagement/smappservice/opensystemsettingsloginitems()
- [S8] https://developer.apple.com/videos/play/wwdc2022/10096/ (What's new in privacy)
- [S9] https://nilcoalescing.com/blog/LaunchAtLoginSetting (onAppear + appearsActive status refresh)
- [S10] Local SDK headers: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/ServiceManagement.framework/Headers/SMAppService.h`, `SMErrors.h`, `SMLoginItem.h`
- [S11] https://developer.apple.com/documentation/servicemanagement/smappservice/register() and https://developer.apple.com/forums/thread/779379
- [S12] https://developer.apple.com/forums/thread/713830 (Apple DTS: Open at Login vs Allow in the Background; clean-machine testing)
- [S13] Local SDK header `CoreServices.framework/.../SharedFileList.framework/.../LSSharedFileList.h` (deprecation macros)
- [S14] https://github.com/rxhanson/Rectangle/blob/main/Rectangle/LaunchOnLogin.swift
- [S15] https://github.com/MrKai77/Loop/blob/main/Loop/App/LaunchAtLoginManager.swift
- [S16] https://github.com/sindresorhus/LaunchAtLogin-Modern (Sources/LaunchAtLogin/LaunchAtLogin.swift, readme)
- [S17] https://github.com/jordanbaird/Ice/blob/main/Ice/Settings/SettingsPanes/GeneralSettingsPane.swift
- [S18] https://github.com/p0deje/Maccy/blob/master/Maccy/Settings/GeneralSettingsPane.swift
- [S19] https://developer.apple.com/forums/thread/760186 (Apple DTS: user-controlled login item; notFound after user disable)
- [S20] https://github.com/kitlangton/scrawl/issues/20 (notFound for never-registered app in /Applications, macOS 27.0.1)
- [S21] https://github.com/lemacarl/unreality/pull/69 and https://github.com/martonpaulo/meantime/issues/32 (ad-hoc signing, DerivedData, notFound handling; anecdotal)
- [S22] https://github.com/sindresorhus/LaunchAtLogin-Legacy/issues/100 (100+ duplicate items from unsigned builds)
- [S23] https://developer.apple.com/forums/thread/726826 (Apple DTS: status 78, delete stale builds)
- [S24] https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement
- [S25] Local SDK header `CoreServices.framework/.../AE.framework/.../AERegistry.h` (`keyAELaunchedAsLogInItem`)
