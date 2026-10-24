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

  /// AC-092: full-screen and no-entry are no-ops. No write, one `.restore` log line, entry kept.
  @Test @WindowActor func noOpReasons() {
    // Full-screen focused window with an entry.
    var full = Rig()
    full.capture()
    let entry = OriginalFrameEntry(key: full.key, frame: Self.original, via: .mouse)
    #expect(
      RestorePlanner.plan(
        entry, window: full.ref(), facts: Self.facts(fullScreen: true), topology: Self.oneDisplay)
        == .failure(.fullScreen))
    #expect(full.restoreFocused(facts: Self.facts(fullScreen: true)) == .noOp(.fullScreen))
    #expect(full.ws.calls.isEmpty)
    #expect(full.registry.entry(full.key) == entry)
    #expect(full.sink.events.count == 1)
    let line = full.sink.events.first
    #expect(line?.category == .restore)
    #expect(line?.level == .info)
    #expect(line?.message.contains("fullScreen") == true)
    #expect(line?.pid == getpid())
    #expect(line?.bundleID == "com.example.app")

    // No entry at all.
    var empty = Rig()
    #expect(empty.restoreFocused() == .noOp(.noEntry))
    #expect(empty.ws.calls.isEmpty)
    #expect(empty.registry.entry(empty.key) == nil)
    #expect(empty.sink.events.count == 1)
    #expect(empty.sink.events.first?.category == .restore)
    #expect(empty.sink.events.first?.message.contains("noEntry") == true)

    // Facts not yet read (nil) do not block a Restore.
    var unknown = Rig()
    unknown.capture()
    unknown.ws.enqueue(.frame(.value(Self.original)))
    #expect(unknown.restoreFocused(facts: nil) == .applied(Self.original))
    #expect(unknown.sink.events.isEmpty)
  }

  /// AC-094: a single-Zone Snap and a Span Snap leave the same kind of entry; Restore returns the same frame.
  @Test @WindowActor func spanAndSnapShareMemory() {
    var rig = Rig()
    let single = WindowKey(pid: rig.handle.pid, elementHash: 11)
    let span = WindowKey(pid: rig.handle.pid, elementHash: 12)
    let spanFrame = CGRect(x: 0, y: 25, width: 1920, height: 1055)

    // Both windows start at the same frame; each Snap captures it, then records the applied frame.
    for (key, zones, frame) in [(single, Set([1]), Self.zoneFrame), (span, Set([1, 2]), spanFrame)] {
      let captured = rig.registry.capture(
        OriginalFrameEntry(key: key, frame: Self.original, via: .mouse))
      #expect(captured)
      rig.registry.recordSnap(
        LastSnapRecord(key: key, display: Self.displayKey, zones: zones, frame: frame))
    }
    let singleEntry = rig.registry.entry(single)
    let spanEntry = rig.registry.entry(span)
    #expect(singleEntry?.frame == spanEntry?.frame)
    #expect(singleEntry?.via == spanEntry?.via)
    #expect(rig.registry.lastSnap(single)?.zones.count == 1)
    #expect(rig.registry.lastSnap(span)?.zones.count == 2)

    var results: [RestoreResult] = []
    for key in [single, span] {
      rig.ws.enqueue(.frame(.value(Self.original)))
      results.append(
        rig.service.restoreFocused(
          registry: &rig.registry, key: key, window: rig.ref(), facts: Self.facts(),
          handle: rig.handle, topology: Self.oneDisplay, mode: .full, health: &rig.health))
    }
    #expect(results == [.applied(Self.original), .applied(Self.original)])
    #expect(rig.registry.entry(single) == nil)
    #expect(rig.registry.entry(span) == nil)
  }

  static let display2Key = DisplayKey.uuid("22222222-2222-4222-8222-222222222222")

  /// Display 1 at the origin, Display 2 to its right; only Display 1 has a menu bar.
  static let twoDisplays = TopologySnapshot(
    displays: [
      oneDisplay.displays[0],
      DisplaySnapshot(
        key: display2Key, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1920, y: 0, width: 2560, height: 1440), scale: 1, isMain: false,
        mirrorOf: nil, name: "Side", resolution: CGSize(width: 2560, height: 1440)),
    ], separateSpaces: true, primaryFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))

  /// AC-095: an Original Frame on a vanished Display lands inside the Display the window is on now.
  @Test @WindowActor func clampsOntoOccupiedDisplay() throws {
    let display2 = Self.twoDisplays.displays[1]
    let gone = CGRect(x: 6000, y: 200, width: 700, height: 500)  // a Display that is no longer connected
    let onDisplay2 = CGRect(x: 2400, y: 300, width: 900, height: 600)
    var rig = Rig()
    let entry = OriginalFrameEntry(key: rig.key, frame: gone, via: .mouse)

    let planned = RestorePlanner.plan(
      entry, window: rig.ref(frame: onDisplay2), facts: Self.facts(), topology: Self.twoDisplays)
    let target = try #require(try? planned.get())
    #expect(display2.visibleFrame.contains(target))
    #expect(target.size == gone.size)
    #expect(target != gone)

    // The service writes the clamped target and reports clamped; the entry is forgotten.
    rig.capture(gone)
    rig.ws.enqueue(.frame(.value(target)))
    let result = rig.service.restoreFocused(
      registry: &rig.registry, key: rig.key, window: rig.ref(frame: onDisplay2), facts: Self.facts(),
      handle: rig.handle, topology: Self.twoDisplays, mode: .full, health: &rig.health)
    #expect(result == .clamped(target))
    #expect(rig.ws.calls == Self.writes(target, rig.handle))
    #expect(rig.registry.entry(rig.key) == nil)

    // In-bounds: returned unchanged.
    let inBounds = CGRect(x: 100, y: 100, width: 800, height: 600)
    let same = RestorePlanner.plan(
      OriginalFrameEntry(key: rig.key, frame: inBounds, via: .keyboard), window: rig.ref(frame: onDisplay2),
      facts: Self.facts(), topology: Self.twoDisplays)
    #expect(same == .success(inBounds))

    // Straddling two Displays still intersects one: not clamped.
    let straddle = CGRect(x: 1500, y: 200, width: 900, height: 600)
    let both = RestorePlanner.plan(
      OriginalFrameEntry(key: rig.key, frame: straddle, via: .mouse), window: rig.ref(frame: onDisplay2),
      facts: Self.facts(), topology: Self.twoDisplays)
    #expect(both == .success(straddle))

    // A frame larger than the Display shrinks to fit its visible frame.
    let huge = CGRect(x: 9000, y: 9000, width: 5000, height: 3000)
    let shrunk = try #require(
      try? RestorePlanner.plan(
        OriginalFrameEntry(key: rig.key, frame: huge, via: .mouse), window: rig.ref(frame: onDisplay2),
        facts: Self.facts(), topology: Self.twoDisplays
      ).get())
    #expect(display2.visibleFrame.contains(shrunk))
  }

  /// ADR-0016 property: for random Display layouts and Original Frames, `plan` either returns the frame
  /// unchanged (it already meets a Display) or a rect inside some Display's visible frame.
  @Test @WindowActor func planAlwaysLandsOnADisplay() {
    var gen = Generator(seed: 0x24_0A11)
    let key = WindowKey(pid: 77, elementHash: 7)
    for round in 0..<300 {
      // Displays laid side by side with random sizes, a menu bar inset on top.
      var displays: [DisplaySnapshot] = []
      var x = Double(gen.int(-2000...0))
      for index in 0..<gen.int(1...3) {
        let w = Double(gen.int(800...3000)), h = Double(gen.int(600...1800))
        let frame = CGRect(x: x, y: 0, width: w, height: h)
        let bar = Double(gen.int(0...40))
        displays.append(
          DisplaySnapshot(
            key: .uuid("D\(round)-\(index)"), frame: frame,
            visibleFrame: CGRect(x: x, y: bar, width: w, height: h - bar), scale: 1, isMain: index == 0,
            mirrorOf: nil, name: "D", resolution: frame.size))
        x += w
      }
      let topology = TopologySnapshot(
        displays: displays, separateSpaces: true, primaryFrame: displays[0].frame)
      let original = CGRect(
        x: gen.int(-8000...8000), y: gen.int(-5000...5000), width: gen.int(100...4000),
        height: gen.int(100...2500))
      let current = gen.pick(displays).frame.insetBy(dx: 10, dy: 10)
      let ref = ZonesCore.WindowRef(
        id: WindowID(rawValue: 1), pid: 77, bundleID: nil, frame: current, layer: 0)
      let planned = RestorePlanner.plan(
        OriginalFrameEntry(key: key, frame: original, via: .mouse), window: ref, facts: Self.facts(),
        topology: topology)
      guard case .success(let target) = planned else {
        Issue.record("round \(round): plan failed for a non-full-screen window")
        continue
      }
      let intersects = displays.contains {
        let overlap = original.intersection($0.frame)
        return !overlap.isNull && overlap.width * overlap.height > 0
      }
      if intersects {
        #expect(target == original, "round \(round): an on-Display frame must not move")
      } else {
        #expect(
          displays.contains { $0.visibleFrame.contains(target) },
          "round \(round): \(target) is outside every visible frame")
      }
    }
  }
}
