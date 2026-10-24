import CoreGraphics
import Foundation
import ZonesCore
import ZonesTestSupport
import ZonesWindowing
import os

@testable import Zones

final class MemoryPreferenceStorage: PreferenceStorage {
  private let data = OSAllocatedUnfairLock<Data?>(initialState: nil)
  func load() -> Data? { data.withLock { $0 } }
  func save(_ new: Data) { data.withLock { $0 = new } }
}

@MainActor
final class RecordingSurfaces: PermissionSurfaces {
  enum Call: Hashable { case badge(Bool), grant(Bool), showOnboarding, dismissOnboarding, relaunch(Bool) }
  var calls: [Call] = []
  func setBadge(_ on: Bool) { calls.append(.badge(on)) }
  func setGrantMenuItem(_ on: Bool) { calls.append(.grant(on)) }
  func showOnboarding() { calls.append(.showOnboarding) }
  func dismissOnboarding() { calls.append(.dismissOnboarding) }
  func offerRelaunch(_ on: Bool) { calls.append(.relaunch(on)) }
}

@MainActor
final class RecordingDiagnostics: DiagnosticsPresenter {
  enum Call: Hashable { case preview(String), copy(String) }
  var calls: [Call] = []
  var confirm = true
  func showPreview(_ text: String) -> Bool {
    calls.append(.preview(text))
    return confirm
  }
  func copy(_ text: String) { calls.append(.copy(text)) }
}

/// A full set of fakes behind a `CompositionAdapters`. Everything is quiet until a test scripts it.
@MainActor
final class Harness {
  let clock = FakeClock()
  let input: FakeInputSource
  let windows: FakeWindowSystem
  let enumerator: FakeWindowEnumerator
  let displays: FakeDisplayProvider
  let overlay: FakeOverlayPresenter
  /// Wraps the fake overlay (to observe ordering against other fakes); defaults to the fake itself.
  var overlayOverride: (any OverlayPresenter)?
  let hotkeys: FakeHotkeyRegistrar
  let probe: FakePermissionProbe
  let files = FakeFileSystem()
  let surfaces = RecordingSurfaces()
  let diagnostics = RecordingDiagnostics()
  let preferences = MemoryPreferenceStorage()
  let uiLog = OSAllocatedUnfairLock(initialState: [String]())
  let running = OSAllocatedUnfairLock(initialState: [RecoveryRecord]())
  let frontmost = OSAllocatedUnfairLock<(name: String, bundleID: String)?>(initialState: nil)

  init() {
    input = FakeInputSource(clock: clock)
    windows = FakeWindowSystem(clock: clock)
    enumerator = FakeWindowEnumerator(clock: clock)
    displays = FakeDisplayProvider(clock: clock)
    overlay = FakeOverlayPresenter(clock: clock)
    hotkeys = FakeHotkeyRegistrar(clock: clock)
    probe = FakePermissionProbe(clock: clock)
  }

  var adapters: CompositionAdapters {
    let log = uiLog
    let running = running
    let frontmost = frontmost
    return CompositionAdapters(
      clock: clock, input: input, windows: windows, enumerator: enumerator, displays: displays, overlay: overlayOverride ?? overlay,
      hotkeys: hotkeys, probe: probe, files: files, supportDirectory: URL(filePath: "/zones-support"),
      preferences: preferences, surfaces: surfaces, diagnostics: diagnostics,
      ui: UIActions(
        openSettings: { log.withLock { $0.append("settings") } },
        openEditor: { log.withLock { $0.append("editor") } },
        requestQuit: { log.withLock { $0.append("quit") } }),
      ownPid: 999_999, runningApps: { running.withLock { $0 } }, bundleID: { _ in nil }, identify: { _ in nil },
      accessibilityOptions: { AccessibilityOptions(reduceTransparency: false, reduceMotion: false) },
      bundleInfo: { BundleInfo(version: "1.0", build: "1", signingIdentity: "ad-hoc", macOS: "27.0.0") },
      frontmost: { frontmost.withLock { $0 } }, cursor: { .zero })
  }

  func makeRoot() -> CompositionRoot { CompositionRoot(adapters: adapters) }
}
