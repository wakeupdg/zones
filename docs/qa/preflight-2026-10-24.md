# QA preflight: Zones on this machine (2026-10-24, ~4:40-4:47 AM PT)
Repo: "/Users/dganesh/!MY PROJECTS/open-source-clones/fancy-zones", branch integration, git status clean afterwards.

## 1. Build  -> WORKS
- `xcodegen generate` -> "Created project at .../Zones.xcodeproj"
- `scripts/q.sh xcodebuild -quiet -project Zones.xcodeproj -scheme Zones -configuration Debug -derivedDataPath .build/DerivedData CODE_SIGN_IDENTITY="Zones Dev" build`
  -> only warning "Using the first of multiple matching destinations (arm64)"; `[q.sh] exit=0`
- App: /Users/dganesh/!MY PROJECTS/open-source-clones/fancy-zones/.build/DerivedData/Build/Products/Debug/Zones.app
- `codesign -dvv`: Identifier=com.dganesh.zones, Mach-O arm64, flags=0x10000(runtime), Authority=Zones Dev, TeamIdentifier=not set
- `security find-identity -v -p codesigning` -> 1 valid: 22A4D61CE3F62FD9D543F7AC1A8102EA2F952476 "Zones Dev"

## 2. Launch  -> WORKS (alive after 10 s)
- Ran binary directly: `Zones.app/Contents/MacOS/Zones >launch.out 2>launch.err &` (pid 33510)
- After `sleep 10`: `ps` STAT=SN (alive); `pgrep -x Zones` -> 23716, 33510
- launch.out and launch.err are both EMPTY (0 lines). The app writes NOTHING to stdout/stderr.
- GOTCHA: pid 23716 was ALREADY running before I started: a stale build from the T33 worktree
  (/Users/dganesh/!MY PROJECTS/open-source-clones/.zones-worktrees/T33/.build/.../Zones.app, started 3:50 AM).
  Same bundle id, so `pgrep -x Zones` / `pkill -x Zones` / `open -n` are ambiguous. Use the PID of your own process.
  Earlier T36 worktree run (pid 27112, 4:41 AM) also appears in the unified log.
- Logging: os.Logger via Sources/ZonesWindowing/Diagnostics/UnifiedLogSink.swift, **subsystem is "Zones"** (NOT
  com.dganesh.zones), categories core, layout, windowing, input, permission, topology, snap, restore, shortcuts,
  overlay, diagnostics, app. No file logs, no ~/Library/Logs. Messages are `.public`.
  - `log show --predicate 'subsystem == "com.dganesh.zones"' --last 5m` -> empty (header only).
  - `/usr/bin/log show --predicate 'subsystem == "Zones"' --last 5m --info --debug` -> only
    "[Zones:<cat>] probe" lines from swiftpm-testing-helper (unit tests). My app pid 33510 emitted ZERO
    subsystem-"Zones" lines in the first minute (grep'd with processID == 33510; 1 line = header).
  - NOTE: in zsh bare `log` fails ("too many arguments", shell builtin); always use /usr/bin/log.
- Real launch evidence (system lines only), e.g. for pid 33510:
  `04:45:28.054 (TCC) TCCAccessRequest() ... service=kTCCServiceListenEvent`
  `04:45:28.290 (TCC) TCCAccessRequest() ... service=kTCCServiceAccessibility, target_token={pid:33510...}`

## 3. Accessibility trust / windows / screenshot
- TRUSTED. Replies to pid 33510 for kTCCServiceAccessibility and kTCCServiceListenEvent:
  `auth_value => 2, result => true, auth_reason => 4` (allowed), no prompt shown.
  (For contrast, the older T36 pid 27112 got ListenEvent `auth_value 0, result false` - different build/state.)
  Grant exists for the "Zones Dev"-signed bundle com.dganesh.zones. App source calls AXIsProcessTrusted in
  Sources/ZonesWindowing/Adapters/AXPermissionProbe.swift:19 but does not log the result.
- Onboarding window: NOT verifiable. System Events is blocked:
  `osascript -e 'tell application "System Events" to get name of every window of process "Zones"'`
  -> `execution error: System Events got an error: osascript is not allowed assistive access. (-1728)`
  (count windows variant gives -25211). It is the calling host (this terminal/agent) lacking Accessibility,
  not -1743 Automation. `osascript -e 'tell application "Finder" to get name of startup disk'` DOES work
  ("Macintosh HD") so Apple-event Automation to Finder is allowed; only UI scripting (assistive access) is not.
- `lsappinfo info -only StatusLabel Zones` -> returns ASN with all fields [NULL] (UIElement/agent app, no label).
  `lsappinfo list | grep -i zones` shows both instances (T33 stale and mine) with bundleID com.dganesh.zones.
  App is ApplicationType=UIElement (LSUIElement, menu-bar only, no Dock icon).
- Screenshot: `/usr/sbin/screencapture -x shot.png` (NOT /usr/bin/screencapture - that path does not exist) -> rc=0,
  13,831,018 bytes, 6016x3384 px (`sips -g pixelHeight` = 3384). No permission dialog appeared.
  BUT it is a WALLPAPER-ONLY image: viewed downscaled, it shows a sunset-mountain desktop picture with NO menu bar,
  NO app windows, NO Zones status item. So size > 50 KB is true but misleading; this host process lacks Screen
  Recording permission (other apps' windows are masked). Screenshots cannot verify Zones UI from here.
  Files: scratchpad/shot.png, scratchpad/shot_small.png.
- `cliclick` not installed.

## 4. `run` skill
- `~/.claude/skills/run/SKILL.md` does NOT exist; `ls ~/.claude/skills | grep -i run` -> only jev-context-pruner.
  `run` is a built-in skill from the harness list: "Launch and drive this project's app ... first looks for a project
  skill that already covers launching the app; otherwise falls back to built-in patterns per project type (CLI,
  server, TUI, Electron, browser-driven, library)". No file to quote; no macOS-menu-bar-app specific recipe found.
- Practical equivalents here: launch via binary or `open -n`; drive via mcp__computer-use__* (needs request_access
  per app, "full" tier for Zones, and the harness needs Screen Recording + Accessibility) or ios-sim (not relevant).
  Those MCP tools are deferred; I did not load/try them (out of scope for the no-human check).

## 5. tccutil
- `tccutil reset Accessibility com.dganesh.zones` -> "Successfully reset Accessibility approval status for com.dganesh.zones", rc=0.
- WARNING: this REVOKES the existing Accessibility grant seen in section 3. The next launch will likely be untrusted
  and may show the onboarding / system prompt (a human must re-approve in System Settings > Privacy > Accessibility).
  I did not relaunch after the reset, so the untrusted path is unobserved.
  (Subsequent `log show` of tccd lines just echoed the reset message, many repeats; harmless.)

## 6. Quit and artifacts
- I stopped only my own process: `kill 33510`. I did NOT run `pkill -x Zones` because it would also kill the
  pre-existing stale T33 instance (pid 23716), which is still running (pgrep -x Zones -> 23716). Kill it with
  `kill 23716` if you want a clean slate.
- `ls ~/Library/Application\ Support/Zones* ~/Library/Preferences/com.dganesh.zones*` -> no matches for either;
  `defaults read com.dganesh.zones` -> "Domain ... not found". No ~/Library/*/com.dganesh.zones* dirs. The app
  created no files in a 10 s run (DocumentStore in Sources/ZonesCore/DocumentStore.swift writes json lazily).
- git status --short: empty (no tracked changes). Build products live in .build/ (ignored).

## What a QA agent CAN do unattended
- xcodegen + xcodebuild + codesign ("Zones Dev" valid): yes.
- Launch binary, check liveness by PID: yes. Read os_log via `/usr/bin/log show --predicate 'subsystem == "Zones"'`.
- Read TCC verdict from `log show --predicate 'processID == <pid> AND eventMessage CONTAINS "RECV"'`.
- osascript to Finder: yes.
## What it CANNOT do here
- System Events UI scripting / window enumeration (-1728 assistive access).
- Meaningful screenshots of Zones (screencapture returns wallpaper only; no Screen Recording).
- Re-grant Accessibility after tccutil reset (needs human).
