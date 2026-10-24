import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

/// AC-076: the crash-recovery record for Enhanced UI.
@Suite struct EnhancedUIRecoveryTests {
  static let directory = URL(filePath: "/zones-test")
  static let file = directory.appending(path: "enhanced-ui-recovery.json")
  static let launch = Date(timeIntervalSince1970: 1_700_000_000.25)

  struct Rig {
    let fs = FakeFileSystem()
    let store: DocumentStore
    let recovery: EnhancedUIRecovery

    init() {
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
}
