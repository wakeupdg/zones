# Zones — shared interface contracts (v1)

Swift 6, strict concurrency. Every type below is `Sendable`; value types are `Hashable` and, where persisted, `Codable`.
Names here are the contract: implement them as written, extend by adding, never rename. Bodies are omitted; a ticket
implements the types its `contracts` list names and consumes the rest. LI-020: every rule is a pure function over value
types; the OS sits behind the seams in §3, each with one production adapter and one scriptable fake in `ZonesTestSupport`.

## 0. Modules and placement

```
ZonesCore  ->  ZonesLayout  ->  ZonesWindowing  ->  App (XcodeGen, App/)      ZonesTestSupport depends on all three.
Sources/ZonesCore        value types, documents, preferences, Clock, Log, FileSystem, CoordinateSpace     (no AppKit)
Sources/ZonesLayout      tree math, templates, grid, hit test, span, validator, editor engine/model, stores (no AppKit)
Sources/ZonesWindowing   Seams/ (protocols), Adapters/ (production: AX, CG, tap, Carbon, SMAppService), WindowActor,
                         Drag/, Snap/, Restore/, Exclusion/, Permission/, Topology/, Shortcuts/, Overlay/, Diagnostics/, Shell/
Sources/ZonesTestSupport Generator, Fixtures, Fakes/                 Tests/<Target>Tests (Swift Testing, `swift test`)
App/                     wiring only: @main, composition root, NSPanel subclass, SwiftUI views. AppTests/ via xcodebuild.
```
Rules: `import ApplicationServices` and `CGWindowList*` appear only under `Sources/ZonesWindowing/Adapters/` (AC-162). The single
`@unchecked Sendable` is `WindowHandle` (§3.0, AC-161); fakes use `OSAllocatedUnfairLock<State>` or actor isolation. Every `CGRect`/
`CGPoint` crossing a seam is in **AppKit global coordinates** (origin bottom-left of the primary display); only `CoordinateSpace` (§1.1)
converts to AX space and only the AX adapter calls it. Named constants live in `Constants` (§1.9), referenced, never re-typed.

## 1. ZonesCore value types

### 1.1 Geometry and coordinates
```swift
public struct UnitRect: Hashable, Codable, Sendable { public var x, y, width, height: Double }   // fractions of a rect, 0...1
public struct RGBA: Hashable, Codable, Sendable { public var r, g, b, a: Double }
public enum CoordinateSpace {   // the ONE conversion (AC-164). primaryFrame = TopologySnapshot.primaryFrame
  public static func axRect(_ appKit: CGRect, primaryFrame: CGRect) -> CGRect
  public static func appKitRect(_ ax: CGRect, primaryFrame: CGRect) -> CGRect
  public static func display(for rect: CGRect, in snapshot: TopologySnapshot) -> DisplaySnapshot?  // max intersection area
  public static func panelLocal(_ appKit: CGRect, panelFrame: CGRect) -> CGRect
}
```

### 1.2 Layout tree (ADR-0003 as amended)
```swift
public struct LayoutID: Hashable, Codable, Sendable, RawRepresentable { public let rawValue: String }  // UUID string, or "builtin:<template>:<count>"
public enum SplitAxis: String, Codable, Sendable { case horizontal /* side by side: first = left */, vertical /* stacked: first = top */ }
public indirect enum SplitNode: Hashable, Codable, Sendable {
  case leaf                                                                   // a Zone; no payload, numbers are derived
  case split(axis: SplitAxis, ratio: Double, first: SplitNode, second: SplitNode)   // ratio in (0,1) = first's share
}
public struct NodePath: Hashable, Codable, Sendable { public var steps: [Bool] }  // false = first, true = second; [] = root
public struct Insets: Hashable, Codable, Sendable { public var margin: Double; public var gap: Double }   // points
public struct Surround: Hashable, Codable, Sendable { public var top, left, bottom, right: Double }     // fractions, each 0...0.45
public struct BuiltInRef: Hashable, Sendable { public var template: Template; public var count: Int }  // never encoded
public struct Layout: Hashable, Codable, Sendable, Identifiable { public var id: LayoutID; public var name: String; public var root: SplitNode
  public var surround: Surround; public var insets: Insets   // explicit on every persisted Layout (never nil)
  public var builtIn: BuiltInRef? }                            // nil for custom; built-ins never reach layouts.json
public struct Zone: Hashable, Sendable { public var number: Int; public var path: NodePath; public var frame: CGRect }  // frame: AppKit, grid-rounded
public struct ResolvedLayout: Hashable, Sendable { public var layoutID: LayoutID; public var display: DisplayKey; public var visibleFrame: CGRect
  public var layoutRect: CGRect; public var scale: Double; public var zones: [Zone] }   // sorted by number, 1...N
public enum Template: String, Codable, CaseIterable, Sendable {   // rawValue = CONTEXT.md glossary name
  case columns = "Columns", rows = "Rows", grid = "Grid", priorityGrid = "Priority Grid", focus = "Focus"
  public var counts: [Int] }   // columns/rows 2...5, grid [4, 9], priorityGrid [3], focus [1]
```

### 1.3 Displays, topology, assignments (ADR-0012, ADR-0014)
```swift
public enum DisplayKey: Hashable, Sendable { case uuid(String), unstable(String) }     // unstable: session only, never encoded
public struct PersistentDisplayKey: Hashable, Codable, Sendable { public let uuid: String }  // decoder rejects non-UUID (AC-123)
public struct DisplaySnapshot: Hashable, Sendable { public var key: DisplayKey; public var frame: CGRect; public var visibleFrame: CGRect; public var scale: Double
  public var isMain: Bool; public var mirrorOf: DisplayKey?; public var name: String; public var resolution: CGSize }
public struct TopologySnapshot: Hashable, Sendable { public var displays: [DisplaySnapshot]; public var separateSpaces: Bool; public var primaryFrame: CGRect
  public func display(_ key: DisplayKey) -> DisplaySnapshot? }
public struct Assignment: Hashable, Codable, Sendable { public var layout: LayoutID; public var displayName: String; public var lastVisibleFrame: CGRect
  public var lastScale: Double; public var lastSeen: Date? }
```

### 1.4 Windows (facts only; no titles ever, LI-003)
```swift
public struct WindowID: Hashable, Sendable { public let rawValue: UInt32 }               // CGWindowID, session only
public struct WindowRef: Hashable, Sendable {   // phase-1 (CoreGraphics) facts
  public var id: WindowID; public var pid: pid_t; public var bundleID: String?; public var frame: CGRect; public var layer: Int32 }
public enum Subrole: String, Sendable { case standard, dialog, systemDialog, systemFloatingWindow, floating, sheet, popover, unknown }
public struct WindowFacts: Hashable, Sendable {   // phase-2 (Accessibility) facts
  public var subrole: Subrole; public var isFullScreen: Bool; public var positionSettable: Bool; public var sizeSettable: Bool }
public struct WindowKey: Hashable, Sendable { public var pid: pid_t; public var elementHash: Int }   // registry key (CFHash of the element)
public enum CapturePath: String, Codable, Sendable { case mouse, keyboard }; public struct OriginalFrameEntry: Hashable, Sendable { public var key: WindowKey; public var frame: CGRect; public var via: CapturePath }
public struct LastSnapRecord: Hashable, Sendable { public var key: WindowKey; public var display: DisplayKey; public var zones: Set<Int>; public var frame: CGRect }
```

### 1.5 Preferences, modifiers, shortcuts, appearance (ADR-0008, ADR-0010, ADR-0017)
```swift
public enum Modifier: String, Codable, CaseIterable, Sendable { case shift, control, option, command }
public struct ModifierSet: OptionSet, Hashable, Codable, Sendable { public let rawValue: UInt8   // masked to the four (AC-051)
  public static let shift, control, option, command: ModifierSet; public init(_ m: Modifier); public static func masked(_ cgFlags: UInt64) -> ModifierSet }
public enum Key: Hashable, Codable, Sendable { case digit(Int), letter(String), arrowLeft, arrowRight, arrowUp, arrowDown, comma }
public struct Chord: Hashable, Codable, Sendable { public var key: Key; public var modifiers: ModifierSet; public var hasCommandOrControl: Bool }  // LI-018
public enum ShortcutAction: Hashable, Codable, Sendable, CaseIterable { case sendToZone(Int), cycleRight, cycleLeft, restore, openEditor, openSettings
  public var isWindowAction: Bool }   // true for the first four (registered only while granted, AC-105)
public struct Shortcut: Hashable, Codable, Sendable { public var action: ShortcutAction; public var chord: Chord? }  // nil = cleared
public enum EnhancedUIPolicy: String, Codable, Sendable { case toggle, leave }
public struct Appearance: Hashable, Codable, Sendable { public var fill: RGBA; public var opacity: Double; public var defaultInsets: Insets }
public enum NoticeFlag: String, Codable, Sendable { case modifiersCoerced, preferencesCoerced, separateSpacesOff }
public typealias ExclusionRule = String         // one bundle identifier
public struct Preferences: Hashable, Codable, Sendable {   // defaults: schema 1, shift, control, ShortcutRules.defaults, .toggle
  public var schemaVersion: Int; public var activationModifier: Modifier; public var spanModifier: Modifier   // coerced to differ (AC-087)
  public var shortcuts: [Shortcut]; public var appearance: Appearance; public var exclusions: Set<ExclusionRule>
  public var enhancedUI: EnhancedUIPolicy; public var notices: Set<NoticeFlag>; public static let defaults: Preferences }
public enum PreferencesCodec {   // UserDefaults key "zones.preferences" holds the JSON blob; decode coerces field by field (AC-153)
  public static func decode(_ data: Data) -> (Preferences, coercedFields: [String]); public static func encode(_ p: Preferences) -> Data }
```

### 1.6 Typed results and errors (US-139)
```swift
public enum NoOpReason: String, Codable, Sendable { case sameFrame, zoneAbsent, noEntry, fullScreen, excluded, positionNotSettable, windowAbsent, notIdle }
public enum FrameWriteResult: Hashable, Sendable { case applied(CGRect), clamped(CGRect), refused(Int32), timedOut, elementGone, noOp(NoOpReason) }
public enum AXStatus: Hashable, Sendable { case ok, timedOut, elementGone, apiDisabled, refused(Int32) }
public enum AXRead<T: Hashable & Sendable>: Hashable, Sendable { case value(T), timedOut, elementGone, apiDisabled, refused(Int32) }
public enum SkipReason: String, Codable, CaseIterable, Sendable {   // phase 1
  case ownProcess, systemAgent, excludedBundle, unresponsive, ambiguousMatch
  case nonStandardSubrole, sheetOrPopover, systemDialog, fullScreen, positionNotSettable }        // phase 2
public enum SnapMode: String, Codable, Sendable { case full, positionOnly }
public enum Verdict: Hashable, Sendable { case allow(SnapMode), skip(SkipReason) }
public enum LayoutFault: Hashable, Sendable { case ratioOutOfRange(NodePath), leafTooSmall(NodePath), surroundOutOfRange, overlap, emptyName }
public enum DocumentError: Error, Hashable, Sendable { case corrupt(String), newerVersion(found: Int, supported: Int), invalidLayout(name: String, LayoutFault), nonUUIDKey(String), io(String) }
public enum EditorError: Hashable, Sendable { case notSiblings(hint: String), tooSmall, rootMerge, invalidRatio, nothingSelected }
public enum LoginItemError: Error, Hashable, Sendable { case launchDeniedByUser, invalidSignature, other(String) }
```

### 1.7 Clock, Log, FileSystem (seams that live in ZonesCore)
```swift
public enum TimerID: String, Codable, Sendable { case trustPoll, healthTick, suspectResolve, relaunchGate, deadTapRetry, nilUUIDRetry, topologyDebounce, frameSample, unresponsiveCooldown }
public struct TimerHandle: Hashable, Sendable { public let id: TimerID; public let token: UInt64 }
public protocol Clock: Sendable { var now: TimeInterval { get }   // monotonic seconds
  func schedule(_ id: TimerID, after seconds: TimeInterval, repeats: Bool, _ fire: @Sendable @escaping () -> Void) -> TimerHandle
  func cancel(_ handle: TimerHandle) }
public enum LogCategory: String, Codable, CaseIterable, Sendable { case core, layout, windowing, input, permission, topology, snap, restore, shortcuts, overlay, diagnostics, app }
public enum LogLevel: String, Codable, Sendable { case debug, info, notice, error }
public struct LogEvent: Hashable, Codable, Sendable {   // has NO title field, ever (AC-154)
  public var time: TimeInterval; public var category: LogCategory; public var level: LogLevel; public var message: String
  public var bundleID: String?; public var pid: Int32?; public var skip: SkipReason? }
public protocol LogSink: Sendable { func write(_ event: LogEvent) }
public struct EventRing: Sendable { public init(capacity: Int = Constants.ringCapacity); public mutating func append(_ e: LogEvent); public var events: [LogEvent]
  public var skipCounts: [String: [SkipReason: Int]] }                                      // grouped by bundle identifier
public final class Log: Sendable {   // facade: one category per module; sinks = UnifiedLogSink (production) | ArrayLogSink (tests)
  public static let shared: Log; public func install(sink: any LogSink); public func event(_ e: LogEvent); public func ring() -> EventRing
  public static func skip(_ reason: SkipReason, _ ref: WindowRef?, category: LogCategory) }   // one event per skip (AC-155)
public protocol FileSystem: Sendable { func read(_ url: URL) throws -> Data; func writeAtomic(_ data: Data, to url: URL) throws
  func move(_ from: URL, to: URL) throws; func exists(_ url: URL) -> Bool; func remove(_ url: URL) throws }
```

### 1.8 Documents v1 (ADR-0017). One codec for disk and export
```swift
public struct ZonesDocument: Hashable, Codable, Sendable {   // layouts.json carries layouts; assignments.json carries assignments; export may carry both
  public var version: Int /* Constants.documentVersion */; public var layouts: [Layout] /* custom only */; public var assignments: [String: Assignment] /* key = display UUID */ }
public enum DocumentKind: String, Sendable { case layouts = "layouts.json", assignments = "assignments.json", recovery = "enhanced-ui-recovery.json" }
public enum LoadResult: Hashable, Sendable { case loaded(ZonesDocument), migrated(ZonesDocument, from: Int, backup: String), defaults(quarantined: String), newerLeftUntouched(version: Int) }
public struct DocumentStore: Sendable {   // dir = ~/Library/Application Support/Zones; writes are synchronous and atomic (AC-150); backup "<kind>.<yyyyMMdd-HHmmss>.bak"
  public init(fs: any FileSystem, directory: URL, clock: any Clock); public func load(_ kind: DocumentKind) -> LoadResult
  public func save(_ doc: ZonesDocument, as kind: DocumentKind) throws(DocumentError); public func backupName(_ kind: DocumentKind, now: TimeInterval) -> String }
public enum Migrator { public static func migrate(_ raw: Data) -> Result<(ZonesDocument, from: Int), DocumentError> }  // golden fixtures per version (AC-152)
```
JSON shapes (field names are the contract):
```json
layouts.json      {"version":1,"layouts":[{"id":"<uuid>","name":"Desk","surround":{"top":0,"left":0,"bottom":0,"right":0},
                    "insets":{"margin":8,"gap":8},"root":{"kind":"split","axis":"horizontal","ratio":0.5,
                    "first":{"kind":"leaf"},"second":{"kind":"split","axis":"vertical","ratio":0.5,"first":{"kind":"leaf"},"second":{"kind":"leaf"}}}}]}
assignments.json  {"version":1,"assignments":{"37D8832A-2D66-02CA-B9F7-8F30A301B230":{"layout":"builtin:priorityGrid:3","displayName":"Studio Display",
                    "lastVisibleFrame":{"x":0,"y":0,"width":2560,"height":1415},"lastScale":2,"lastSeen":"2026-10-24T17:02:00Z"}}}
export            same document with both arrays; built-in ids: builtin:columns:<2-5> rows:<2-5> grid:<4|9> priorityGrid:3 focus:1
```

### 1.9 Constants
```swift
public enum Constants { public static let documentVersion = 1, preferencesSchema = 1
  public static let perAppTimeout = 0.25, processTimeout = 1.0, unresponsiveCooldown = 10.0, suspectWindow = 3.0
  public static let relaunchGateFailures = 3, relaunchGateWindow = 10.0, topologyDebounce = 0.2, reenableLimit = 5, reenableWindow = 60.0
  public static let deadTapRetry = 30.0, healthTick = 5.0, trustPoll = 1.0, sampleInterval = 1.0 / 60, candidateCap = 4, settleSamples = 3
  public static let minFraction = 1.0 / 12, usableSize = CGSize(width: 120, height: 80), dividerSnapRadius = 6.0
  public static let focusSurround = 0.2, surroundMax = 0.45, ringCapacity = 200, frameTolerance = 1.0, cycleTolerance = 2.0, numberingEpsilon = 1e-6 }
```

## 2. ZonesLayout pure functions (LI-020)
```swift
public enum LayoutMath {   // resolve = surround -> insets -> Grid.round -> numbering
  public static func unitRects(_ root: SplitNode) -> [(path: NodePath, rect: UnitRect)]          // leaves tile the unit square
  public static func layoutRect(visibleFrame: CGRect, surround: Surround) -> CGRect
  public static func resolve(_ layout: Layout, display: DisplaySnapshot) -> ResolvedLayout
  public static func resolve(_ layout: Layout, key: DisplayKey, visibleFrame: CGRect, scale: Double) -> ResolvedLayout }
public enum ZoneNumbering { public static func numbers(_ rects: [(path: NodePath, rect: UnitRect)]) -> [NodePath: Int] }  // row-major, epsilon (AC-099)
public enum Grid {   // dividers and gap rounded once to 1/scale; shared dividers; mirror-symmetric (AC-068, AC-069)
  public static func round(_ rects: [(path: NodePath, rect: UnitRect)], layoutRect: CGRect, insets: Insets, scale: Double) -> [(path: NodePath, frame: CGRect)] }
public enum Hit: Hashable, Sendable { case zone(Int), nearest(Int), none }   // none only outside the visible frame
public enum HitTest { public static func hit(_ point: CGPoint, in layout: ResolvedLayout) -> Hit   // nearest = min edge distance, ties to lower number (AC-080)
  public static func display(at point: CGPoint, in snapshot: TopologySnapshot) -> DisplayKey? }
public enum Span { public static func rect(_ zones: Set<Int>, in layout: ResolvedLayout) -> CGRect }   // bounding union incl. gaps (AC-081)
public enum Templates {   // ids "builtin:<camelCase>:<count>", deterministic order (AC-114); Focus: one leaf, surround 0.2
  public static func builtInID(_ t: Template, count: Int) -> LayoutID; public static func generate(_ t: Template, count: Int, insets: Insets) -> Layout
  public static func all(insets: Insets) -> [Layout]; public static func duplicate(_ l: Layout, insets: Insets, newID: LayoutID) -> Layout }  // "<name> copy", builtIn nil
public enum LayoutValidator { public static func validate(_ l: Layout) -> LayoutFault? }          // ratios in (0,1), min 1/12, surround <= 0.45
public struct ZoneLabel: Hashable, Sendable { public var number: Int; public var text: String; public var frame: CGRect; public var outline: RGBA; public var contentsScale: Double; public var noChord: Bool }
public enum LabelModel { public static func labels(_ r: ResolvedLayout, appearance: Appearance) -> [ZoneLabel] }  // shared by Overlay and editor (AC-132)
public enum EditorCommand: Hashable, Sendable { case select(NodePath?), split(SplitAxis), merge, setRatio(NodePath, Double, snap: Bool), nudge(NodePath, points: Double)
  case setMargin(Double), setGap(Double), template(Template, count: Int), rename(String) }
public struct EditorDraft: Hashable, Sendable { public var layout: Layout; public var selection: NodePath?; public var dirty: Bool }
public enum EditorEngine {   // one command, one new draft, or an error leaving the draft unchanged
  public static func apply(_ c: EditorCommand, to d: EditorDraft, geometry: (visibleFrame: CGRect, scale: Double)) -> Result<EditorDraft, EditorError>
  public static func snappedRatio(_ ratio: Double, candidates: [Double], parentExtentPoints: Double) -> Double   // 1/2,1/3,1/4, collinear (AC-128)
  public static func warnings(_ r: ResolvedLayout) -> Set<Int>                                                   // numbers under 120x80 pt
}
public struct EditorState: Hashable, Sendable { public var draft: EditorDraft; public var undo: [EditorDraft]; public var redo: [EditorDraft]
  public var display: DisplayKey; public var visibleFrame: CGRect; public var scale: Double; public var preview: ResolvedLayout; public var warnings: Set<Int> }
public enum EditorEvent: Hashable, Sendable { case command(EditorCommand), undo, redo, switchDisplay(DisplayKey, confirmed: Bool), assign, save, cancel }
public enum EditorEffect: Hashable, Sendable { case promptUnsaved(DisplayKey), writeLayouts(ZonesDocument), writeAssignment(PersistentDisplayKey, LayoutID), replaceLive(Layout), close, error(EditorError) }
public enum EditorModel {
  public static func open(_ l: Layout, display: DisplayKey, topology: TopologySnapshot, assignments: [String: Assignment]) -> EditorState  // disconnected: stored geometry (AC-125)
  public static func reduce(_ s: EditorState, _ e: EditorEvent, context: (topology: TopologySnapshot, document: ZonesDocument)) -> (EditorState, [EditorEffect])
}
public struct LayoutStore: Hashable, Sendable {   // in-memory truth; built-ins regenerated from defaults (AC-117); callers persist via DocumentStore
  public init(document: ZonesDocument, defaults: Insets)
  public var builtIns: [Layout]; public var custom: [Layout]; public func layout(_ id: LayoutID) -> Layout?
  public mutating func setDefaults(_ i: Insets); public mutating func upsert(_ l: Layout)
  public mutating func delete(_ id: LayoutID, replacement: LayoutID?, assignments: inout [String: Assignment]) -> Result<Void, DocumentError>   // AC-115
  public var document: ZonesDocument
}
public enum AssignmentLookup { public static func layoutID(for key: DisplayKey, in assignments: [String: Assignment], session: [DisplayKey: LayoutID]) -> LayoutID }  // default builtin:priorityGrid:3
public enum ImportMode: Hashable, Sendable { case merge, replace }
public enum ImportResult: Hashable, Sendable { case applied(ZonesDocument, backup: String?, dormant: [String]), refused(DocumentError) }
public enum ImportExport {
  public static func export(_ store: LayoutStore, assignments: [String: Assignment], only: LayoutID?) -> ZonesDocument
  public static func importDocument(_ incoming: ZonesDocument, into current: ZonesDocument, mode: ImportMode, attached: Set<String>, newID: () -> LayoutID, now: TimeInterval) -> ImportResult
}
```

## 3. ZonesWindowing

### 3.0 Handle, actor, seams
```swift
public final class WindowHandle: @unchecked Sendable, Hashable {   // THE one unchecked box (AC-161); wraps AXUIElement
  public let pid: pid_t; public var key: WindowKey; public init(element: AXUIElement, pid: pid_t) }
public struct WindowRecord: Hashable, Sendable { public var ref: WindowRef; public var handle: WindowHandle; public var facts: WindowFacts? }
@globalActor public actor WindowActor { public static let shared: WindowActor }    // ADR-0015: every AX call is @WindowActor; UI is @MainActor
public enum AXNotice: Hashable, Sendable { case destroyed(WindowKey), appTerminated(pid_t), moved(WindowKey), apiDisabled }
public protocol WindowSystem: Sendable {   // Accessibility. Production: AXWindowSystem. Fake: FakeWindowSystem
  @WindowActor func setTimeouts(perApp: TimeInterval, processWide: TimeInterval)              // at launch (AC-159)
  @WindowActor func element(at point: CGPoint) -> WindowHandle?; @WindowActor func windows(of pid: pid_t) -> [WindowHandle]
  @WindowActor func focusedWindow() -> WindowHandle?
  @WindowActor func frame(_ h: WindowHandle) -> AXRead<CGRect>; @WindowActor func frames(_ hs: [WindowHandle]) -> [WindowKey: AXRead<CGRect>]  // one batched call per tick
  @WindowActor func facts(_ h: WindowHandle) -> AXRead<WindowFacts>
  @WindowActor func setPosition(_ p: CGPoint, _ h: WindowHandle) -> AXStatus; @WindowActor func setSize(_ s: CGSize, _ h: WindowHandle) -> AXStatus
  @WindowActor func enhancedUI(pid: pid_t) -> AXRead<Bool?>; @WindowActor func setEnhancedUI(_ on: Bool, pid: pid_t) -> AXStatus   // nil = attribute absent
  @WindowActor func trivialRead() -> AXStatus                                                  // heartbeat / recovery probe
  func notices() -> AsyncStream<AXNotice> }
public protocol WindowEnumerator: Sendable {   // CoreGraphics list. Production: CGWindowEnumerator. Fake: FakeWindowEnumerator
  func onScreenWindows() -> [WindowRef]; func windows(ids: [WindowID]) -> [WindowRef]            // layer 0, front to back; no names requested
  func candidates(under point: CGPoint, hint: WindowID?) -> [WindowRef] }                       // hint first, then hit test; z-ordered; uncapped
public enum InputKind: Hashable, Sendable { case leftDown, leftDragged, leftUp, flagsChanged }
public struct InputEvent: Hashable, Sendable { public var kind: InputKind; public var point: CGPoint; public var flags: ModifierSet; public var windowUnderPointer: WindowID?; public var time: TimeInterval }
public struct TapConfig: Hashable, Sendable { public var listenOnly: Bool; public var mask: Set<InputKind>; public static let production: TapConfig }  // AC-065
public enum TapStart: Hashable, Sendable { case started, unavailable }
public enum TapSignal: Hashable, Sendable { case disabledByTimeout, disabledByUserInput, recreated(Bool) }
public protocol InputSource: Sendable {   // Production: EventTapInputSource. Fake: FakeInputSource
  var config: TapConfig { get }; func start() -> TapStart; func stop(); func reenable() -> Bool; func recreate() -> TapStart
  var events: AsyncStream<InputEvent> { get }; var signals: AsyncStream<TapSignal> { get } }
public enum RawDisplayChange: Hashable, Sendable { case reconfiguration, screenParameters, activeSpace, wake }
public protocol DisplayProvider: Sendable {   // Production: ScreenDisplayProvider. Fake: FakeDisplayProvider
  func snapshot() -> TopologySnapshot; var changes: AsyncStream<RawDisplayChange> { get } }   // fresh read; nil uuid -> .unstable after retries
public protocol OverlayPresenter: Sendable {   // Production: App's PanelOverlayPresenter. Fake: FakeOverlayPresenter
  @MainActor func show(_ scene: OverlayScene); @MainActor func highlight(_ h: Highlight); @MainActor func hide()
  @MainActor func reassert(); @MainActor func orderOut(); @MainActor func resize(to snapshot: TopologySnapshot) }
public enum HotkeyRegistration: Hashable, Sendable { case registered, inUse, invalid }
public protocol HotkeyRegistrar: Sendable {   // Production: CarbonHotkeyRegistrar. Fake: FakeHotkeyRegistrar
  @MainActor func register(_ chord: Chord, for action: ShortcutAction) -> HotkeyRegistration
  @MainActor func unregister(_ action: ShortcutAction); @MainActor func bound(_ action: ShortcutAction) -> Chord?; var presses: AsyncStream<ShortcutAction> { get } }
public enum LoginItemStatus: Hashable, Sendable { case enabled, requiresApproval, notFound, notRegistered }
public protocol LoginItemService: Sendable {   // Production: SMLoginItemService. Fake: FakeLoginItemService
  @MainActor func status() -> LoginItemStatus; @MainActor func register() throws(LoginItemError)
  @MainActor func unregister() throws(LoginItemError); @MainActor func openLoginItemsSettings() }
public protocol PermissionProbe: Sendable {   // Production: AXPermissionProbe. Fake: FakePermissionProbe
  func isTrusted() -> Bool; @MainActor func openAccessibilitySettings(); var launchedAtLogin: Bool { get } }
```
Fake contract (AC-163): every fake exposes `enqueue(_ response)`, `calls: [Call]` (an enum per seam), `latency: TimeInterval`
applied through the injected `FakeClock`, and `reset()`. `FakeClock` exposes `pending: [TimerID]`, `advance(by:)`, `fire(_:)`.

### 3.1 Drag Session reducer (ADR-0006, 0007, 0009)
```swift
public struct ModifierConfig: Hashable, Sendable { public var activation: Modifier; public var span: Modifier }   // read at mouseDown only (AC-111)
public struct SpanState: Hashable, Sendable { public var zones: Set<Int>; public var display: DisplayKey?; public var frozen: Bool; public var suspended: Bool }
public struct Highlight: Hashable, Sendable { public var display: DisplayKey?; public var primary: Set<Int>; public var secondary: Set<Int>; public var dimAll: Bool }
public struct OverlayScene: Hashable, Sendable { public var layouts: [ResolvedLayout]; public var appearance: Appearance; public var options: AccessibilityOptions }
public struct AccessibilityOptions: Hashable, Sendable { public var reduceTransparency: Bool; public var reduceMotion: Bool }
public enum SampleResult: Hashable, Sendable { case frame(CGRect, WindowFacts?), timedOut, gone }
public struct ArmContext: Hashable, Sendable { public var topology: TopologySnapshot; public var layouts: [DisplayKey: ResolvedLayout]; public var appearance: Appearance; public var options: AccessibilityOptions; public var hasOriginalFrame: Bool }
public enum DragState: Hashable, Sendable {
  case idle
  case pressed(candidates: [WindowRef], down: CGPoint, downFrames: [WindowID: CGRect], flags: ModifierSet, config: ModifierConfig, samples: Int, retried: Bool)
  case moving(window: WindowRef, downFrame: CGRect, flags: ModifierSet, config: ModifierConfig)
  case armed(window: WindowRef, downFrame: CGRect, flags: ModifierSet, config: ModifierConfig, context: ArmContext, display: DisplayKey?, hit: Hit, span: SpanState, point: CGPoint?)
}
public enum DragEvent: Hashable, Sendable {
  case mouseDown(point: CGPoint, flags: ModifierSet, candidates: [WindowRef], phaseOne: Verdict, config: ModifierConfig)
  case dragged(point: CGPoint, flags: ModifierSet), mouseUp(point: CGPoint, flags: ModifierSet), flagsChanged(ModifierSet)
  case frameSample([WindowID: SampleResult])          // one batched read per tick; facts ride with the first moved sample
  case armContext(ArmContext)                         // the driver answers requestArmContext
  case windowGone, topologyChanged(ArmContext), spaceChanged, wake
}
public enum DragEffect: Hashable, Sendable {
  case requestSample([WindowID]), stopSampling, requestArmContext(window: WindowRef, point: CGPoint)
  case showOverlay(OverlayScene), updateHighlight(Highlight), hideOverlay, reassertPanels
  case snap(SnapPlan), restore(WindowRef, downFrame: CGRect), skip(SkipReason, WindowRef?), log(String)
}
public enum DragSessionReducer { public static func reduce(_ s: DragState, _ e: DragEvent) -> (DragState, [DragEffect]) }   // pure; no Clock, no actor
```
Guarantees: `hideOverlay` precedes `snap`/`restore` in the mouseUp step (AC-053); `showOverlay` only on entry to `armed`;
`requestSample` only in `pressed`, never after `moving` (AC-156); highlight == drop set (LI-009).
`armed` stores the last cursor point (`point`, nil right after `armContext`, before the first `dragged`); `topologyChanged` re-hits at it (LI-009).

### 3.2 Snap, write protocol, health, Enhanced UI (ADR-0022, ADR-0015 amended, ADR-0018 amended)
```swift
public struct SnapPlan: Hashable, Sendable { public var window: WindowRef; public var display: DisplayKey; public var zones: Set<Int>; public var target: CGRect
  public var mode: SnapMode; public var via: CapturePath; public var originalFrame: CGRect? }   // mouse path: the mouse-down frame
public struct AppHealth: Hashable, Sendable {   // unresponsive cooldown, Clock-driven (AC-077); consumeRetry = exactly one attempt after the cooldown
  public mutating func markUnresponsive(_ pid: pid_t, now: TimeInterval); public func isUnresponsive(_ pid: pid_t, now: TimeInterval) -> Bool
  public mutating func consumeRetry(_ pid: pid_t, now: TimeInterval) -> Bool }
public struct RecoveryRecord: Hashable, Codable, Sendable { public var bundleID: String; public var pid: Int32; public var launchDate: Date; public var priorEnhancedUI: Bool }
public protocol FrameWriting: Sendable {   // size, position, size, read back; Enhanced UI off/on with defer; retry once then abort
  @WindowActor func write(_ target: CGRect, mode: SnapMode, to h: WindowHandle, policy: EnhancedUIPolicy, health: inout AppHealth, now: TimeInterval) -> FrameWriteResult }
public struct FrameWriter: FrameWriting { public init(system: any WindowSystem, recovery: EnhancedUIRecovery) }; public struct SnapOutcome: Hashable, Sendable { public var result: FrameWriteResult; public var readBack: CGRect? }
public struct SnapService: Sendable {   // noOp when |target - current| <= frameTolerance (AC-079); clamped -> one position follow-up (AC-071)
  public init(writer: any FrameWriting, system: any WindowSystem, clock: any Clock)
  @WindowActor public func execute(_ plan: SnapPlan, handle: WindowHandle, health: inout AppHealth) -> SnapOutcome }
public struct EnhancedUIRecovery: Sendable {   // once per (bundleID, pid, launchDate) per session (AC-076)
  public init(store: DocumentStore); public func noteIfFirst(_ r: RecoveryRecord); public func restoreAtLaunch(running: [RecoveryRecord]) -> [RecoveryRecord]; public func drainAndDelete() }
```

### 3.3 Original Frame registry and Restore (ADR-0009 amended)
```swift
public struct OriginalFrameRegistry: Hashable, Sendable {
  public mutating func capture(_ e: OriginalFrameEntry) -> Bool          // false if an entry exists (never overwrites)
  public mutating func recordSnap(_ r: LastSnapRecord); public func entry(_ k: WindowKey) -> OriginalFrameEntry?; public func lastSnap(_ k: WindowKey) -> LastSnapRecord?
  public mutating func forget(_ k: WindowKey); public mutating func evict(pid: pid_t); public mutating func apply(_ n: AXNotice)
}
public enum RestoreResult: Hashable, Sendable { case applied(CGRect), clamped(CGRect), noOp(NoOpReason), failed(FrameWriteResult) }
public enum RestorePlanner { public static func plan(_ e: OriginalFrameEntry, window: WindowRef, facts: WindowFacts?, topology: TopologySnapshot) -> Result<CGRect, NoOpReason> }  // off-display clamp (AC-095)
public struct RestoreService: Sendable { public init(writer: any FrameWriting, clock: any Clock)
  @WindowActor public func restore(_ e: OriginalFrameEntry, handle: WindowHandle, target: CGRect, mode: SnapMode, health: inout AppHealth) -> RestoreResult }
```

### 3.4 Exclusion policy (ADR-0018 amended)
```swift
public enum ExclusionPolicy {
  public static let systemAgents: Set<String>   // com.apple.dock, com.apple.WindowManager, com.apple.notificationcenterui, com.apple.controlcenter, com.apple.loginwindow, com.apple.UserNotificationCenter
  public static func phaseOne(_ ref: WindowRef, ownPid: pid_t, exclusions: Set<String>, health: AppHealth, now: TimeInterval) -> Verdict   // CG facts only
  public static func phaseTwo(_ facts: WindowFacts) -> Verdict                                                                              // sizeNotSettable -> allow(positionOnly)
}
public enum ExclusionsPaneModel { public struct Row: Hashable, Sendable { public var name: String; public var bundleID: String }
  public static func rows(_ exclusions: Set<String>, names: [String: String]) -> [Row]; public static func add(bundleID: String, to: inout Set<String>) }
```

### 3.5 Permission machine, tap recovery (ADR-0021 amended)
```swift
public enum PermissionState: Hashable, Sendable { case notGranted, granted, suspect(since: TimeInterval), revoked(failures: Int, firstFailure: TimeInterval?), needsRelaunch }
public enum PermissionEvent: Hashable, Sendable { case probe(Bool), apiDisabled, tapNil, tapRecreated(Bool), trivialRead(AXStatus), heartbeat(AXStatus), timer(TimerID), wake, reonboard, quit }
public enum PermissionEffect: Hashable, Sendable { case schedule(TimerID, TimeInterval), cancel(TimerID), probe, heartbeat, startTap, revalidateTap, recreateTap
  case dismissOnboarding, showOnboarding, badge(Bool), grantMenuItem(Bool), offerRelaunch(Bool), registerWindowHotkeys, unregisterWindowHotkeys
  case drainEnhancedUI, forceTopologySnapshot, orderPanelsOut, disableTap, invalidateTap, removeRecoveryRecord }
public struct PermissionConfig: Hashable, Sendable { public var launchedAtLogin: Bool; public var heartbeatEnabled: Bool /* SPK-006 */; public var reducerIdle: Bool }
public enum PermissionMachine { public static func reduce(_ s: PermissionState, _ e: PermissionEvent, config: PermissionConfig, now: TimeInterval) -> (PermissionState, [PermissionEffect]) }
public enum TapState: Hashable, Sendable { case alive, dead, unavailable }; public enum TapRecoveryEffect: Hashable, Sendable { case reenable, recreate, tapLost, tapUnavailable, schedule(TimerID, TimeInterval), cancel(TimerID) }
public struct TapRecovery: Hashable, Sendable { public var state: TapState; public var reenables: [TimeInterval]   // rate limit 5 per 60 s (AC-011)
  public mutating func reduce(_ signal: TapSignal?, timer: TimerID?, now: TimeInterval) -> [TapRecoveryEffect] }
```

### 3.6 Topology monitor (ADR-0012, ADR-0014)
```swift
public enum TopologyEvent: Hashable, Sendable { case raw(RawDisplayChange), snapshot(TopologySnapshot, nilUUIDs: Int), timer(TimerID), assignmentPicked(DisplayKey, LayoutID) }
public enum TopologyEffect: Hashable, Sendable { case schedule(TimerID, TimeInterval), cancel(TimerID), readSnapshot, topologyChanged(TopologySnapshot), resizePanels(TopologySnapshot)
  case persistAssignment(PersistentDisplayKey, Assignment), sessionAssignment(DisplayKey, LayoutID), notice(NoticeFlag) }
public struct TopologyState: Hashable, Sendable { public var current: TopologySnapshot?; public var previous: TopologySnapshot?; public var uuidRetries: Int; public var session: [DisplayKey: LayoutID]; public var noticed: Set<NoticeFlag> }
public enum TopologyMonitor { public static func reduce(_ s: TopologyState, _ e: TopologyEvent, assignments: [String: Assignment], now: TimeInterval) -> (TopologyState, [TopologyEffect]) }  // mirror -> master key (AC-122)
public struct LayoutsPaneModel: Hashable, Sendable { public enum Row: Hashable, Sendable { case attached(DisplaySnapshot, LayoutID, unstable: Bool), disconnected(key: String, Assignment, copyTargets: [DisplayKey]) }
  public static func rows(_ t: TopologySnapshot, assignments: [String: Assignment], session: [DisplayKey: LayoutID]) -> [Row] }
```

### 3.7 Shortcuts (ADR-0010, ADR-0011)
```swift
public enum ChordWarning: String, Sendable { case commandOnly, commandShiftOnly, controlOnlyWithArrowOrDigit }; public enum RecorderState: Hashable, Sendable { case accepted, warning(ChordWarning), conflict(duplicate: ShortcutAction), rejected }
public enum ShortcutRules { public static func validate(_ c: Chord) -> Bool; public static func recorderState(_ c: Chord, for a: ShortcutAction, bound: [Shortcut]) -> RecorderState
  public static let defaults: [Shortcut] }   // AC-097
public enum ShortcutStoreEvent: Hashable, Sendable { case set(ShortcutAction, Chord?), registration(ShortcutAction, HotkeyRegistration), permission(granted: Bool), reducerIdle(Bool), launch }
public enum ShortcutStoreEffect: Hashable, Sendable { case register(Chord, ShortcutAction), unregister(ShortcutAction), failed(ShortcutAction, HotkeyRegistration), persist([Shortcut]) }
public struct ShortcutStoreState: Hashable, Sendable { public var shortcuts: [Shortcut]; public var registered: Set<ShortcutAction>; public var granted: Bool; public var idle: Bool; public var queued: [ShortcutStoreEvent] }
public enum ShortcutStore { public static func reduce(_ s: ShortcutStoreState, _ e: ShortcutStoreEvent) -> (ShortcutStoreState, [ShortcutStoreEffect]) }   // diff re-registers only changed (AC-111)
public enum CommandPlan: Hashable, Sendable { case snap(SnapPlan), restore(OriginalFrameEntry, target: CGRect), noOp(NoOpReason) }
public struct FocusedWindow: Hashable, Sendable { public var record: WindowRecord; public var facts: WindowFacts; public var frame: CGRect }   // read-back before any write
public enum CycleDirection: Sendable { case left, right }
public enum CycleResolver { public static func base(_ last: LastSnapRecord?, frame: CGRect, layout: ResolvedLayout) -> Int?   // 2 pt match, else max intersection
  public static func next(from base: Int?, direction: CycleDirection, count: Int, span: Set<Int>?) -> Int }   // wrap (AC-100)
public enum ShortcutResolver { public static func plan(_ a: ShortcutAction, focused: FocusedWindow?, verdict: Verdict, topology: TopologySnapshot, layouts: [DisplayKey: ResolvedLayout], registry: OriginalFrameRegistry) -> CommandPlan }
public enum ShortcutDispatcher { public static func dispatch(_ a: ShortcutAction, reducerIdle: Bool) -> Result<ShortcutAction, NoOpReason> }   // notIdle dropped, one log (AC-110)
```

### 3.8 Overlay model (ADR-0023)
```swift
public struct ZoneDrawing: Hashable, Sendable { public var number: Int; public var rect: CGRect; public var fill: RGBA; public var label: ZoneLabel }
public struct PanelStyle: Hashable, Sendable { public var idle: RGBA; public var highlight: RGBA; public var secondary: RGBA; public var dim: RGBA; public var animationDuration: Double? }
public struct PanelModel: Hashable, Sendable { public var display: DisplayKey; public var frame: CGRect; public var zones: [ZoneDrawing]; public var style: PanelStyle; public var spanOutline: Bool }
public enum OverlayModel { public static func panels(_ s: OverlayScene) -> [PanelModel]   // rects inside visibleFrame, panel = full frame (AC-059); highlight distinct at 0.10 (AC-042)
  public static func apply(_ h: Highlight, to panels: [PanelModel]) -> [PanelModel] }
```

### 3.9 Diagnostics and shell models
```swift
public struct DiagnosticsReport: Hashable, Codable, Sendable { public var version, build, signingIdentity, macOS, permission, tap: String; public var displays: [DisplaySnapshotReport]
  public var assignments: [String: Assignment]; public var preferences: Preferences; public var events: [LogEvent]; public var skipCounts: [String: [SkipReason: Int]]; public func render() -> String }
public struct DisplaySnapshotReport: Hashable, Codable, Sendable { public var key: String; public var frame: CGRect; public var visibleFrame: CGRect; public var scale: Double }
public enum DiagnosticsEffect: Hashable, Sendable { case preview(String), copy(String) }   // preview always first (AC-154)
public enum Diagnostics { public static func report(bundle: BundleInfo, permission: PermissionState, tap: TapState, topology: TopologySnapshot?, assignments: [String: Assignment], prefs: Preferences, ring: EventRing) -> DiagnosticsReport }
public struct BundleInfo: Hashable, Sendable { public var version: String; public var build: String; public var signingIdentity: String /* or "ad-hoc" */; public var macOS: String }
public enum MenuItem: Hashable, Sendable { case header(String), layout(LayoutID, title: String, checked: Bool), excludeApp(name: String, bundleID: String, checked: Bool), editLayouts, settings, grantAccessibility, about, quit, separator }
public enum MenuModel { public static func build(cursorDisplay: DisplaySnapshot?, assignment: LayoutID, store: LayoutStore, frontmost: (name: String, bundleID: String)?, exclusions: Set<String>, permission: PermissionState) -> [MenuItem] }  // zero actor calls (AC-017)
public struct StatusItemModel: Hashable, Sendable { public var badged: Bool; public var isTemplate: Bool; public static func derive(_ p: PermissionState, tap: TapState) -> StatusItemModel }
public enum GeneralPaneModel { public static func statusRows(_ p: PermissionState, tap: TapState) -> [(label: String, value: String)] }   // exactly two (AC-019)
public struct LoginItemToggleModel: Hashable, Sendable { public var isOn: Bool; public var caption: String?; public var showLoginItemsButton: Bool; public var disabled: Bool
  public static func derive(_ s: LoginItemStatus, error: LoginItemError?) -> LoginItemToggleModel }
public struct AboutModel: Hashable, Sendable { public var version, build, signingIdentity, license: String; public var attribution: String  /* exactly one line containing "FancyZones" */ }
public enum LifecycleEffect: Hashable, Sendable { case disableTap, invalidateTap, orderPanelsOut, drainEnhancedUI, removeRecoveryRecord, revalidateTap, probe, forceTopologySnapshot }
public enum AppLifecycle { public static func quitEffects() -> [LifecycleEffect]; public static func wakeEffects() -> [LifecycleEffect] }   // AC-026 order
public enum WindowPlacement { public static func settingsFrame(cursor: DisplaySnapshot, size: CGSize) -> CGRect; public static func editorFrame(cursor: DisplaySnapshot) -> CGRect }  // AC-022
```

## 4. ZonesTestSupport
```swift
public struct Generator: Sendable {   // ADR-0016: seeded, shrink-free, reproducible; tree() is always valid (min fraction 1/12)
  public init(seed: UInt64); public mutating func next() -> UInt64; public mutating func int(_ r: ClosedRange<Int>) -> Int
  public mutating func double(_ r: ClosedRange<Double>) -> Double; public mutating func bool() -> Bool; public mutating func pick<T>(_ xs: [T]) -> T
  public mutating func tree(maxDepth: Int, minFraction: Double = Constants.minFraction) -> SplitNode; public mutating func layout(maxDepth: Int) -> Layout
  public mutating func rect(in bounds: CGRect) -> CGRect; public mutating func dragEvents(count: Int, context: ArmContext, config: ModifierConfig) -> [DragEvent]
  public static func failureMessage(seed: UInt64, layout: Layout, note: String) -> String }   // contains "seed=<int>" and layout description (AC-165)
public enum Fixtures { public static let threeDisplays: TopologySnapshot   // primary 1x (0,0,1920,1080) centered; 2x (-1440,0,1440,900) left; 1x portrait (-600,1080,1080,1920) above, negative origin
  public static func layouts(_ t: TopologySnapshot, _ l: Layout) -> [DisplayKey: ResolvedLayout]; public static let nineZone: Layout }
public final class FakeClock: Clock, Sendable { public init(); public var pending: [TimerID] { get }; public func advance(by: TimeInterval); public func fire(_ id: TimerID) }
// Fakes/: FakeWindowSystem (@WindowActor), FakeWindowEnumerator, FakeInputSource, FakeDisplayProvider, FakeOverlayPresenter (@MainActor),
//         FakeHotkeyRegistrar (@MainActor), FakeLoginItemService (@MainActor), FakePermissionProbe, FakeFileSystem (failAfterBytes:), ArrayLogSink
```

## 5. LI-020 rule-to-function index
| Rule | Function (module) | Rule | Function (module) |
|---|---|---|---|
| Zone numbering | `ZoneNumbering.numbers` (Layout) | Hit test / nearest | `HitTest.hit` (Layout) |
| Span union | `Span.rect` (Layout) | Snap plan | `SnapService.execute`, `FrameWriter.write` (Windowing) |
| Exclusion | `ExclusionPolicy.phaseOne/phaseTwo` (Windowing) | Drag Session | `DragSessionReducer.reduce` (Windowing) |
| Cycle base | `CycleResolver.base/next` (Windowing) | Permission state | `PermissionMachine.reduce`, `TapRecovery.reduce` (Windowing) |
| Template generation | `Templates.generate/all/builtInID` (Layout) | Migration | `Migrator.migrate`, `PreferencesCodec.decode` (Core) |
| Topology | `TopologyMonitor.reduce` (Windowing) | Editor | `EditorEngine.apply`, `EditorModel.reduce` (Layout) |
