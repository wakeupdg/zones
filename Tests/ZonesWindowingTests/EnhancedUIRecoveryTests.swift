import ApplicationServices
import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing
import os

/// AC-076: the crash-recovery record for Enhanced UI.
@Suite struct EnhancedUIRecoveryTests {
  static let directory = URL(filePath: "/zones-test")
  static let file = directory.appending(path: "enhanced-ui-recovery.json")
  static let launch = Date(timeIntervalSince1970: 1_700_000_000.25)

  struct Rig {
    let fs: FakeFileSystem
    let store: DocumentStore
    let recovery: EnhancedUIRecovery

    init(failAfterBytes: Int? = nil) {
      fs = FakeFileSystem(failAfterBytes: failAfterBytes)
      store = DocumentStore(fs: fs, directory: EnhancedUIRecoveryTests.directory, clock: FakeClock())
      recovery = EnhancedUIRecovery(store: store)
    }

    var writes: Int {
      fs.calls.filter { if case .writeAtomic = $0 { true } else { false } }.count
    }

    func stored() -> [RecoveryRecord]? {
      guard let data = fs.files[EnhancedUIRecoveryTests.file] else { return nil }
      return try? JSONDecoder().decode([RecoveryRecord].self, from: data)
    }

    func seed(_ records: [RecoveryRecord]) throws {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      try store.saveRaw(try encoder.encode(records), as: .recovery)
    }
  }

  static func record(
    _ bundle: String = "com.example.a", pid: Int32 = 100, launch: Date = launch, prior: Bool = true
  ) -> RecoveryRecord {
    RecoveryRecord(bundleID: bundle, pid: pid, launchDate: launch, priorEnhancedUI: prior)
  }

  @Test func writeOnceRestoreOnMatch() throws {
    let rig = Rig()
    let first = Self.record()

    // (a) the first note writes the file: one atomic write, one record.
    rig.recovery.noteIfFirst(first)
    #expect(rig.writes == 1)
    #expect(rig.stored() == [first])

    // (b) the same key again writes nothing, even with a different prior value.
    rig.recovery.noteIfFirst(first)
    rig.recovery.noteIfFirst(Self.record(prior: false))
    #expect(rig.writes == 1)

    // (c) another pid, launch date or bundle id is a new key; the file holds all of them.
    let otherPid = Self.record(pid: 101)
    let otherLaunch = Self.record(launch: Self.launch.addingTimeInterval(5))
    let otherBundle = Self.record("com.example.b")
    rig.recovery.noteIfFirst(otherPid)
    rig.recovery.noteIfFirst(otherLaunch)
    rig.recovery.noteIfFirst(otherBundle)
    #expect(rig.writes == 4)
    #expect(rig.stored() == [first, otherPid, otherLaunch, otherBundle])

    // (d) restore at launch: only a full match with prior on; stale entries are dropped.
    let fresh = Rig()
    let match = Self.record()
    let falsePrior = Self.record("com.example.off", pid: 7, prior: false)
    try fresh.seed([
      match, Self.record(pid: 999), Self.record(launch: Self.launch.addingTimeInterval(1)),
      Self.record("com.example.other"), falsePrior,
    ])
    let running = [match, falsePrior, Self.record("com.example.b", pid: 5)]
    #expect(fresh.recovery.restoreAtLaunch(running: running) == [match])
    #expect(fresh.fs.files[Self.file] == nil)

    // (e) a missing or corrupt file gives [] without crashing.
    #expect(fresh.recovery.restoreAtLaunch(running: running).isEmpty)
    try fresh.store.saveRaw(Data("not json {".utf8), as: .recovery)
    #expect(fresh.recovery.restoreAtLaunch(running: running).isEmpty)
    #expect(fresh.fs.files[Self.file] == nil)

    // (f) drain removes the file; a second call is harmless.
    rig.recovery.drainAndDelete()
    #expect(rig.fs.files[Self.file] == nil)
    #expect(!rig.fs.exists(Self.file))
    rig.recovery.drainAndDelete()
    #expect(rig.fs.files[Self.file] == nil)
  }

  // MARK: FrameWriter recording

  static let target = CGRect(x: 100, y: 50, width: 400, height: 300)
  static let identity: @Sendable (pid_t) -> (bundleID: String, launchDate: Date)? = { _ in
    ("com.example.a", EnhancedUIRecoveryTests.launch)
  }

  /// A `FrameWriter` over a fake window system and fake disk. `identify` defaults to a fixed app.
  /// `atIdentify` holds the window-system call log as it stood each time the identity was asked for,
  /// which is the moment just before the record is written.
  struct WriterRig {
    let ws: FakeWindowSystem
    let disk: Rig
    let writer: FrameWriter
    let handle: WindowHandle
    let atIdentify = OSAllocatedUnfairLock<[[FakeWindowSystem.Call]]>(initialState: [])
    var health = AppHealth()

    init(
      failAfterBytes: Int? = nil,
      identify: @escaping @Sendable (pid_t) -> (bundleID: String, launchDate: Date)? =
        EnhancedUIRecoveryTests.identity
    ) {
      let fake = FakeWindowSystem(clock: FakeClock())
      let snapshots = atIdentify
      ws = fake
      disk = Rig(failAfterBytes: failAfterBytes)
      writer = FrameWriter(
        system: fake, recovery: disk.recovery,
        identify: { pid in
          snapshots.withLock { $0.append(fake.calls) }
          return identify(pid)
        })
      handle = WindowHandle(element: AXUIElementCreateApplication(getpid()), pid: getpid())
    }

    /// One write; `prior` is what the app reports for Enhanced UI.
    @WindowActor mutating func write(
      prior: AXRead<Bool?>, readBack: CGRect? = EnhancedUIRecoveryTests.target,
      size: AXStatus? = nil, policy: EnhancedUIPolicy = .toggle
    ) -> FrameWriteResult {
      ws.enqueue(.enhancedUI(prior))
      if let size { ws.enqueue(.size(size)) }
      if let readBack { ws.enqueue(.frame(.value(readBack))) }
      return writer.write(
        EnhancedUIRecoveryTests.target, mode: .full, to: handle, policy: policy, health: &health,
        now: 0)
    }
  }

  /// Not an AC: the record is written once per app, after the restore, with the prior value.
  @Test @WindowActor func frameWriterRecordsOncePerApp() {
    // Two Snaps on one app with prior on: one write, prior true, taken after the restore.
    var rig = WriterRig()
    let h = rig.handle
    #expect(rig.write(prior: .value(true)) == .applied(Self.target))
    #expect(rig.disk.writes == 1)
    #expect(rig.disk.stored()?.map(\.priorEnhancedUI) == [true])
    #expect(rig.atIdentify.withLock { $0.first?.last } == .setEnhancedUI(true, h.pid))
    #expect(rig.write(prior: .value(true)) == .applied(Self.target))
    #expect(rig.disk.writes == 1)

    // Prior off is recorded as false.
    var off = WriterRig()
    _ = off.write(prior: .value(false))
    #expect(off.disk.stored()?.map(\.priorEnhancedUI) == [false])

    // Absent attribute, failed read and policy leave: nothing.
    var absent = WriterRig()
    _ = absent.write(prior: .value(nil))
    _ = absent.write(prior: .timedOut)
    _ = absent.write(prior: .value(true), policy: .leave)
    #expect(absent.disk.writes == 0)

    // A refused write is not a completed sequence: no record; the next completed one writes it.
    var refused = WriterRig()
    #expect(refused.write(prior: .value(true), readBack: nil, size: .refused(-25205)) == .refused(-25205))
    #expect(refused.disk.writes == 0)
    _ = refused.write(prior: .value(true))
    #expect(refused.disk.writes == 1)

    // No identity, no record.
    var anonymous = WriterRig(identify: { _ in nil })
    _ = anonymous.write(prior: .value(true))
    #expect(anonymous.disk.writes == 0)
  }

  /// Not an AC: a full disk never reaches the Snap, and nothing is half written.
  @Test @WindowActor func diskFullIsSwallowed() {
    var rig = WriterRig(failAfterBytes: 0)
    #expect(rig.write(prior: .value(true)) == .applied(Self.target))
    #expect(rig.disk.writes == 1)  // attempted
    #expect(rig.disk.stored() == nil)
    #expect(rig.ws.calls.last == .setEnhancedUI(true, rig.handle.pid))
    // The same app is not retried this session: it was noted, even though the write failed.
    #expect(rig.write(prior: .value(true)) == .applied(Self.target))
    #expect(rig.disk.writes == 1)
  }
}
