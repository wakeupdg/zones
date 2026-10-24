# Zones architecture

This is a map of the modules in Zones: what each one offers callers, what it hides, and where its seams are.
It uses the vocabulary of deep modules:

- **Module**: anything with an interface and an implementation (a function, a type, a package).
- **Interface**: everything a caller must know: types, invariants, ordering, error modes, timing.
- **Depth**: how much behavior a caller gets per unit of interface. Deep = small interface, lots of behavior.
- **Seam**: the place where behavior can change without editing that place. **Adapter**: what fills a seam.
- **Leverage** is what callers gain from depth. **Locality** is what maintainers gain: a fix lands in one place.

The exact type signatures live in [CONTRACTS.md](CONTRACTS.md). Words such as Zone, Layout, Display, Span and
Original Frame are defined in [CONTEXT.md](../CONTEXT.md). Decisions are in [adr/](adr/).

## 1. The shape in one picture

```
  macOS: event tap, Carbon hotkeys, NSScreen, Accessibility trust
          |                |                  |                    |
     InputSource    HotkeyRegistrar    DisplayProvider      PermissionProbe      <- OS seams
          v                v                  v                    v
   +-------------+  +----------------+  +-----------------+  +------------------+
   | DragDriver  |  | ShortcutDriver |  | TopologyDriver  |  | PermissionDriver |
   |  Drag-      |  |  ShortcutStore |  |  Topology-      |  |  Permission-     |
   |  Session-   |  |  Dispatcher    |  |  Monitor        |  |  Machine,        |
   |  Reducer    |  |                |  |                 |  |  TapRecovery     |
   +-------------+  +----------------+  +-----------------+  +------------------+
      |       |             |              |          |       startTap, badge,
      |       | sample,     | shortcut     | re-arm   | resize onboarding,
      |       | snap,       |              | drag     | panels window hotkeys
      |       | restore     |              v          |
      |       v             v         (DragDriver)    |
      |   +---------------------------------------+   |
      |   | WindowWorker (WindowActor)            |   |
      |   |  SnapService, RestoreService,         |   |
      |   |  OriginalFrameRegistry, AppHealth     |   |
      |   +---------------------------------------+   |
      |         | AX reads and writes, 250 ms per app  |
      |         v                                      |
      |   WindowSystem, WindowEnumerator   <- OS seams |
      |         v                                      |
      |   macOS: Accessibility, CoreGraphics           |
      |                                                |
      | show, highlight, hide                          |
      v                                                v
   +----------------------------------------------------------+
   | PanelOverlayPresenter (App, MainActor)                   |
   |  one click-through NSPanel per Display                   |
   +----------------------------------------------------------+

   +----------------------------------------------------------+
   | AppState (App, MainActor): the one owner of Preferences, |
   | Layouts and Assignments. Drivers read it; writes go      |
   | straight to DocumentStore (JSON) and UserDefaults.       |
   +----------------------------------------------------------+
```

Each OS seam has a production adapter in `Sources/ZonesWindowing/Adapters/` and a fake in
`Sources/ZonesTestSupport/Fakes/`. The name in the lower half of each driver box is its pure reducer.

Dependency direction: `ZonesCore -> ZonesLayout -> ZonesWindowing -> App`. `ZonesTestSupport` depends on all
three packages and is linked only by tests ([ADR-0002](adr/0002-one-root-package-three-targets.md)).

## 2. Design rules that hold everywhere

1. **Policy lives in pure reducers.** Each runtime concern is a function `reduce(state, event) -> (state, effects)`
   with no clock, no actor and no I/O. Drivers in `App/Composition/` only feed events in and run effects.
2. **Every OS call sits behind a seam with two adapters.** One production adapter and one scriptable fake. Two
   adapters make each seam real, not hypothetical.
3. **Accessibility code is confined.** `import ApplicationServices` and `CGWindowList*` appear only under
   `Sources/ZonesWindowing/Adapters/`. `scripts/hygiene-gate.sh` fails the build otherwise (AC-162).
4. **One coordinate space crosses seams.** Every `CGRect` and `CGPoint` at a seam is in AppKit global
   coordinates. Only `CoordinateSpace` converts to Accessibility space, and only the AX adapter calls it.
5. **Constants are named once** in `ZonesCore/Constants.swift` (timeouts, debounce, minimum Zone size).

## 3. Module map

### 3.1 ZonesCore (`Sources/ZonesCore`, no AppKit)

| | |
|---|---|
| **Interface** | Value types: `Layout`, `SplitNode`, `Surround`, `Insets`, `Template`, `Assignment`, `TopologySnapshot`, `DisplaySnapshot`, `WindowRef`, `Preferences`, `Shortcut`, `Chord`, `ModifierSet`. Documents: `ZonesDocument`, `DocumentStore.load/save`, `Migrator`, `PreferencesCodec.decode`. Seams: `Clock`, `FileSystem`, `LogSink`. |
| **Hides** | JSON field names and sorted-key encoding, version sniffing, migration steps, backup and quarantine file naming, per-field Preferences coercion (one bad field falls back alone), CGEventFlags bit masks. |
| **Seams** | `FileSystem` (`FoundationFileSystem` / `FakeFileSystem`, which can fail after N bytes), `Clock` (App's `ProductionClock` and `SystemClock` / `FakeClock`), `LogSink` (`UnifiedLogSink` / `ArrayLogSink`). |

Depth: `DocumentStore.load(kind)` is one call that returns `LoadResult` (`loaded`, `migrated`, `defaults`,
`newerLeftUntouched`). Behind it sit reading, version checks, migration with a backup written first, and
quarantine of unreadable files. Callers never see a file path or a decoder.

### 3.2 ZonesLayout (`Sources/ZonesLayout`, no AppKit)

| | |
|---|---|
| **Interface** | `LayoutMath.resolve(layout, display) -> ResolvedLayout`, `HitTest.hit/display(at:)`, `Span.rect`, `ZoneNumbering.numbers`, `Templates.generate/all/builtInID`, `LayoutValidator.validate`, `LayoutStore`, `AssignmentLookup.layoutID`, `ImportExport.export/importDocument`, `LabelModel.labels`, and the editor: `EditorEngine.apply`, `EditorModel.reduce`, `UndoStack`. |
| **Hides** | Split-tree to rectangle math, surround and inset application, pixel rounding (`Grid`), row-major numbering, nearest-Zone tie breaks, sibling-only merge, divider snapping, merge/replace import with rename on clash. |
| **Seams** | None to the OS. Everything is a pure function over values, so tests call the interface directly. |

Depth: `HitTest.hit(point, in:)` answers `.zone(n)`, `.nearest(n)` or `.none`. It hides Gap and Margin
handling and the nearest-Zone rule ([ADR-0007](adr/0007-snap-semantics.md),
[ADR-0009](adr/0009-restore-original-frame.md)). The mouse path, the keyboard path and the overlay all use it,
so the highlight always equals the drop set (LI-009).

The editor is two layers. `EditorEngine.apply(command, draft)` is the tree surgery. `EditorModel.reduce` adds
selection, undo and redo, Display switching, save and assign, and emits effects such as `writeLayouts` and
`replaceLive`. The App window turns keys into `EditorEvent`s (`App/Editor/EditorKeyHandling.swift`) and holds
no state.

### 3.3 ZonesWindowing (`Sources/ZonesWindowing`)

This package holds every runtime policy and every OS adapter. Each folder is one module.

| Module | Interface | Hides | Seam and adapters |
|---|---|---|---|
| `Seams/` | Protocols: `WindowSystem`, `WindowEnumerator`, `InputSource`, `DisplayProvider`, `OverlayPresenter`, `HotkeyRegistrar`, `LoginItemService`, `PermissionProbe`; `WindowHandle`; `WindowActor` | Nothing; this is where the external seams live | Each has a production adapter and a fake (below) |
| `Adapters/` | Production adapters: `AXWindowSystem`, `CGWindowEnumerator`, `EventTapInputSource`, `ScreenDisplayProvider`, `CarbonHotkeyRegistrar`, `SMLoginItemService`, `AXPermissionProbe`, `AXObserverBridge` | AX attribute reads, messaging timeouts, AX space conversion, the tap thread and run loop, Carbon registration, window-destroyed observers | Fakes in `ZonesTestSupport/Fakes` |
| `Drag/` | `DragSessionReducer.reduce(DragState, DragEvent) -> (DragState, [DragEffect])` | Candidate resolution under the cursor, mouse-down frame capture, moved detection, arming on the Activation Modifier, Span accumulation and suspension, re-hit after topology change, effect ordering (`hideOverlay` before `snap`) | Pure; tests drive it with event lists |
| `Snap/` | `SnapService.execute(plan, handle, health)`, `FrameWriter.write`, `AppHealth`, `EnhancedUIRecovery` | Size, position, size, read-back protocol; one retry then abort; no-op within tolerance; clamp follow-up; Enhanced UI off and on with a crash record ([ADR-0022](adr/0022-ax-write-protocol.md)) | `FrameWriting` has one adapter (`FrameWriter`), so it is a hypothetical seam; tests go through `FakeWindowSystem` instead |
| `Restore/` | `OriginalFrameRegistry`, `RestorePlanner.plan`, `RestoreService.restore` | Capture-once rule, forget on close and app quit, off-Display clamp | Pure registry and planner; service writes through `FrameWriting` |
| `Exclusion/` | `ExclusionPolicy.phaseOne/phaseTwo`, `ExclusionsPaneModel` | System agents list, own-pid and user exclusions, size-locked windows as position-only ([ADR-0018](adr/0018-automatic-exclusions.md)) | Pure |
| `Permission/` | `PermissionMachine.reduce`, `TapRecovery.reduce` | Trust polling only while not granted, revocation from runtime signals, the suspect window, relaunch gate (3 failures in 10 s), tap re-enable rate limit ([ADR-0021](adr/0021-onboarding-and-permission-loss.md)) | Pure; `PermissionProbe` feeds it |
| `Topology/` | `TopologyMonitor.reduce`, `LayoutsPaneModel.rows` | Debounce, nil-UUID retries, mirror to master key, session-only picks for unstable Displays ([ADR-0012](adr/0012-display-identity-uuid.md), [ADR-0014](adr/0014-topology-changes-and-fullscreen.md)) | Pure; `DisplayProvider` feeds it |
| `Shortcuts/` | `ShortcutStore.reduce`, `ShortcutRules`, `ShortcutDispatcher.dispatch`, `ShortcutResolver.plan`, `CycleResolver` | Chord validation, diff-only re-registration, window shortcuts only while granted, drop while a drag is live, cycle base and wrap, position-only for size-locked windows ([ADR-0010](adr/0010-default-shortcuts.md), [ADR-0011](adr/0011-carbon-hotkeys-no-dependencies.md)) | Pure; `HotkeyRegistrar` is the seam |
| `Overlay/` | `OverlayModel.panels(scene)`, `OverlayModel.apply(highlight, to:)` | Zone rectangles per panel, label placement, idle, highlight, secondary and dim colors ([ADR-0023](adr/0023-overlay-panel-configuration.md)) | Pure; App's `PanelOverlayPresenter` draws the result |
| `Settings/`, `Shell/`, `Diagnostics/` | Pane flows (`LayoutsFlow`, `ShortcutsFlow`), `MenuModel.build`, `StatusItemModel.derive`, `OnboardingViewState`, `AppLifecycle`, `WindowPlacement`, `Diagnostics.report` | Every decision a SwiftUI or AppKit view would otherwise make | Pure; views only render |

Depth example: `DragSessionReducer.reduce` is one function over two enums. Behind it is the whole Drag Session:
press, sample, move, arm, highlight, Span, snap, restore, and recovery from topology, Space and wake changes.
Delete it and that logic would reappear in the driver, the overlay and the window worker. It passes the
deletion test.

### 3.4 App target (`App/`, built by XcodeGen and xcodebuild)

The App target is wiring. It holds no policy that a package could hold.

| Module | Interface | Hides |
|---|---|---|
| `Composition/CompositionRoot` | `init(adapters:)`, `start()`, `wake()`, `quit()` | Object graph, launch order: AX timeouts, Enhanced UI recovery, then the permission probe (the tap starts only after `startTap`) |
| `Composition/AppState` | `preferences`, `layouts`, `assignments`, `document`, `setPreferences`, `upsertLayout`, `deleteLayout`, `replaceDocument`, `reload` | The single owner of persisted truth since T48. Every write goes to its store at once; drivers read, never persist |
| `Composition/DragDriver` | Fed by `InputSource` events, topology and wake | One inbox and one loop, so events reach the reducer strictly in order; the 60 Hz sample timer only while `pressed` |
| `Composition/WindowWorker` | `sample`, `snap`, `restore`, `shortcut` (on `WindowActor`) | Handle matching from CoreGraphics to Accessibility, the Original Frame registry, the `AppHealth` table |
| `Composition/PermissionDriver`, `TopologyDriver`, `ShortcutDriver`, `LifecycleDriver` | One per reducer | One effect, one adapter call; one pending timer per `TimerID` |
| `Overlay/PanelOverlayPresenter` | The `OverlayPresenter` adapter | One click-through `NSPanel` per Display, layers built ahead so the first arm fits one 120 Hz frame |
| `Editor/`, `Settings/`, `Onboarding/`, `StatusItemController` | Windows and views | AppKit and SwiftUI rendering of the pure models above |

App-level seams: `PreferenceStorage` (`UserDefaultsPreferenceStorage` / `MemoryPreferenceStorage`),
`PermissionSurfaces` and `DiagnosticsPresenter` (`AlertDiagnosticsPresenter` / `RecordingDiagnostics`). The
fakes live in `AppTests/Harness.swift`.

### 3.5 ZonesTestSupport (`Sources/ZonesTestSupport`)

| | |
|---|---|
| **Interface** | `Generator(seed:)` (seeded values, valid trees, `dragEvents(count:context:config:)`), `Fixtures` (`threeDisplays`, `nineZone`), `FakeClock` (`pending`, `advance(by:)`, `fire`), and one fake per OS seam in `Fakes/` |
| **Hides** | Reproducible random streams, a three-Display topology with negative origins and mixed scale, scripted answers |
| **Contract** | Every fake has `enqueue(_:)`, `calls`, `latency` applied through `FakeClock`, and `reset()` (AC-163) |

## 4. Runtime data flow

### 4.1 Drag and snap

1. `EventTapInputSource` (listen-only, mouse down, dragged, up and flags changed) yields `InputEvent`s.
2. `DragDriver` posts each one to its inbox and calls `DragSessionReducer.reduce`.
3. On mouse down the reducer asks for frame samples. `WindowWorker` reads frames in one batched call on
   `WindowActor`. The window that moves is the dragged one ([ADR-0006](adr/0006-drag-detection.md)).
4. When the Activation Modifier is down, the reducer asks for an `ArmContext`. The driver builds it from the
   committed topology and `AppState`'s Layouts. The reducer emits `showOverlay`.
5. Each drag event re-hits and emits `updateHighlight`. `PanelOverlayPresenter` repaints the highlight.
6. On mouse up the reducer emits `hideOverlay`, then `snap(plan)` or `restore`. `WindowWorker` runs `SnapService`
   or `RestoreService` on `WindowActor`.

### 4.2 Keyboard

1. `CarbonHotkeyRegistrar` yields a `ShortcutAction`.
2. `ShortcutDispatcher` drops window actions while a drag is live.
3. `WindowWorker.shortcut` reads the focused window, `ShortcutResolver.plan` decides, and the same `SnapService`
   or `RestoreService` writes.

### 4.3 Permission

1. `AXPermissionProbe` answers the 1 s trust poll while not granted.
2. `PermissionMachine` moves `notGranted -> granted` and emits `startTap`, `dismissOnboarding`,
   `registerWindowHotkeys` and `badge(false)`.
3. While granted, runtime signals (a nil tap, an `apiDisabled` result) move to `suspect`, then `revoked` after 3 s.
   That badges the icon, shows onboarding and unregisters the window hotkeys.
4. `TapRecovery` re-enables a disabled tap, at most 5 times per 60 s, then recreates it.

### 4.4 Topology

1. `ScreenDisplayProvider` reports raw changes (reconfiguration, screen parameters, Space, wake).
2. `TopologyMonitor` debounces them, reads a snapshot and emits `resizePanels` and `topologyChanged`.
3. `DragDriver` re-arms a live drag on the new snapshot. No window is moved because of a topology change.
4. New Assignments are written through `AppState`.

## 5. Concurrency

- **`WindowActor`** is a global actor. Every Accessibility call runs on it, so a hung app never blocks the UI
  ([ADR-0015](adr/0015-window-actor-concurrency.md)).
- **250 ms per-app AX messaging timeout** (`Constants.perAppTimeout`), 1 s process-wide. A second timeout in a row
  aborts the Snap, and the app enters a 10 s unresponsive cooldown. One hung app costs at most 0.5 s.
- **`MainActor`** holds all UI, the drivers and `AppState`. The drivers `await` the `WindowActor` but keep one
  inbox each, so an `await` never lets a later event overtake an earlier one.
- **The tap runs on its own thread** and only yields events into an `AsyncStream`.
- **`WindowHandle`** is the one `@unchecked Sendable` type (AC-161). Fakes use locks or actor isolation.

## 6. Persistence

- Documents live in `~/Library/Application Support/Zones/`: `layouts.json` (custom Layouts),
  `assignments.json` (keyed by Display UUID) and `enhanced-ui-recovery.json`.
- Preferences are one JSON value in UserDefaults under `zones.preferences`.
- One encoder for disk and export, with sorted keys so the bytes are stable
  ([ADR-0017](adr/0017-json-persistence.md)).
- Every write goes through `FileSystem.writeAtomic`.
- Migration writes `<name>.<stamp>.bak` first; if the backup fails, the disk is left alone.
- An unreadable file is moved to `<name>.<stamp>.corrupt` and defaults load. A newer version is left untouched,
  and saves over it are refused.
- Built-in Layouts are generated at load and never written.

## 7. Testing strategy

| Layer | How it is tested | Where |
|---|---|---|
| Pure reducers and layout math | Direct calls through the interface: event list in, state and effects out | `Tests/ZonesLayoutTests`, `Tests/ZonesWindowingTests` |
| Property tests | `ReducerInvariantTests` runs 300 seeds x 200 random drag events and checks invariants such as "highlight equals drop set" ([ADR-0016](adr/0016-in-house-property-tests.md)) | `Tests/ZonesWindowingTests/ReducerInvariantTests.swift` |
| Seams | Fakes from `ZonesTestSupport` with scripted answers, latency and `FakeClock`; `FakeContractTests` checks the fakes themselves | `Sources/ZonesTestSupport/Fakes` |
| Documents | Golden fixtures with pinned hashes, migration and quarantine through `FakeFileSystem` | `Tests/ZonesCoreTests/Fixtures` |
| Gate scripts | `GateScriptTests` runs the hygiene, ticket-lint, symbol and plist gate scripts and checks the CI triggers | `Tests/ZonesCoreTests/GateScriptTests.swift` |
| App wiring and AppKit | `AppTests` through `xcodebuild test`, with the harness fakes; covers drivers, panels, windows, VoiceOver labels | `AppTests/` |
| Live OS behavior | Spikes and manual acceptance checks; not automated | `docs/spikes/`, `docs/qa/acs.json` |

`swift test` cannot drive AppKit UI, so window and overlay logic stays behind protocols and pure models. The
App target only renders what those models say.
