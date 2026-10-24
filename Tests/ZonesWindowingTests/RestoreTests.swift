import ApplicationServices
import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesTestSupport

@testable import ZonesWindowing

/// Restore against `FakeWindowSystem` and a real `FrameWriter`. A Restore write is size, position,
/// size, then one read-back, so each test scripts only the read-back frame.
@Suite struct RestoreTests {
  static let original = CGRect(x: 40, y: 80, width: 700, height: 500)
  static let zoneFrame = CGRect(x: 960, y: 25, width: 960, height: 1055)
  static let displayKey = DisplayKey.uuid("11111111-1111-4111-8111-111111111111")

  /// One 1920x1080 Display with a 25 pt menu bar.
  static let oneDisplay = TopologySnapshot(
    displays: [
      DisplaySnapshot(
        key: displayKey, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055), scale: 2, isMain: true,
        mirrorOf: nil, name: "Main", resolution: CGSize(width: 3840, height: 2160))
    ], separateSpaces: true, primaryFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))

  static func facts(fullScreen: Bool = false) -> WindowFacts {
    WindowFacts(
      subrole: .standard, isFullScreen: fullScreen, positionSettable: true, sizeSettable: true)
  }

  struct Rig {
    let clock = FakeClock()
    let ws: FakeWindowSystem
    let handle: WindowHandle
    let service: RestoreService
    let sink = ArrayLogSink()
    let log = Log()
    var health = AppHealth()
    var registry = OriginalFrameRegistry()

    init(pid: pid_t = getpid()) {
      ws = FakeWindowSystem(clock: clock)
      handle = WindowHandle(element: AXUIElementCreateApplication(pid), pid: pid)
      let store = DocumentStore(
        fs: FakeFileSystem(), directory: URL(filePath: "/zones-test"), clock: clock)
      log.install(sink: sink)
      service = RestoreService(
        writer: FrameWriter(system: ws, recovery: EnhancedUIRecovery(store: store)), clock: clock,
        policy: .toggle, log: log)
    }

    var key: WindowKey { handle.key }

    func ref(frame: CGRect = RestoreTests.zoneFrame) -> ZonesCore.WindowRef {
      ZonesCore.WindowRef(
        id: WindowID(rawValue: 1), pid: handle.pid, bundleID: "com.example.app", frame: frame,
        layer: 0)
    }

    /// Capture `frame` as the Original Frame of the rig's window.
    mutating func capture(_ frame: CGRect = RestoreTests.original, via: CapturePath = .mouse) {
      _ = registry.capture(OriginalFrameEntry(key: key, frame: frame, via: via))
    }

    @WindowActor mutating func restoreFocused(
      topology: TopologySnapshot = RestoreTests.oneDisplay, facts: WindowFacts? = RestoreTests.facts(),
      mode: SnapMode = .full
    ) -> RestoreResult {
      service.restoreFocused(
        registry: &registry, key: key, window: ref(), facts: facts, handle: handle,
        topology: topology, mode: mode, health: &health)
    }
  }

  /// The three writes of a full-mode write, then the read-back.
  static func writes(_ frame: CGRect, _ h: WindowHandle) -> [FakeWindowSystem.Call] {
    [.setSize(frame.size, h), .setPosition(frame.origin, h), .setSize(frame.size, h), .frame(h)]
  }

  /// AC-090: the Original Frame goes out through the write protocol; applied and clamped forget it.
  @Test @WindowActor func writesAndRemovesEntry() {
    // applied
    var rig = Rig()
    rig.capture()
    rig.ws.enqueue(.frame(.value(Self.original)))
    #expect(rig.restoreFocused() == .applied(Self.original))
    #expect(rig.ws.calls == Self.writes(Self.original, rig.handle))
    #expect(rig.registry.entry(rig.key) == nil)

    // clamped: the app kept a different size
    var clamped = Rig()
    clamped.capture()
    let accepted = CGRect(x: 40, y: 80, width: 900, height: 600)
    clamped.ws.enqueue(.frame(.value(accepted)))
    #expect(clamped.restoreFocused() == .clamped(accepted))
    #expect(clamped.registry.entry(clamped.key) == nil)

    // refused keeps the entry
    var refused = Rig()
    refused.capture()
    refused.ws.enqueue(.size(.refused(-25205)))
    #expect(refused.restoreFocused() == .failed(.refused(-25205)))
    #expect(refused.registry.entry(refused.key)?.frame == Self.original)

    // timedOut (twice, so the single retry is spent) keeps the entry
    var slow = Rig()
    slow.capture()
    slow.ws.enqueue(.size(.timedOut))
    slow.ws.enqueue(.size(.timedOut))
    #expect(slow.restoreFocused() == .failed(.timedOut))
    #expect(slow.registry.entry(slow.key)?.frame == Self.original)

    // The bare service call writes the given target and returns the mapped result.
    var direct = Rig()
    direct.ws.enqueue(.frame(.value(Self.original)))
    let entry = OriginalFrameEntry(key: direct.key, frame: Self.original, via: .keyboard)
    let result = direct.service.restore(
      entry, handle: direct.handle, target: Self.original, mode: .full, health: &direct.health)
    #expect(result == .applied(Self.original))
  }
}
