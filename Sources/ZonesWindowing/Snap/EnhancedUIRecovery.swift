import Foundation
import ZonesCore
import os

/// Once per (bundleID, pid, launchDate) per session (AC-076). The record lets the next launch turn
/// Enhanced UI back on for an app the previous run left with it off. Copies of the struct share one
/// session state.
public struct EnhancedUIRecovery: Sendable {
  let store: DocumentStore
  private let session = Session()

  public init(store: DocumentStore) { self.store = store }

  private struct Key: Hashable {
    let bundleID: String
    let pid: Int32
    let launchDate: Date
    init(_ r: RecoveryRecord) {
      bundleID = r.bundleID
      pid = r.pid
      launchDate = r.launchDate
    }
  }

  private struct State {
    var noted: Set<Key> = []
    var records: [RecoveryRecord] = []
  }

  private final class Session: Sendable {
    let state = OSAllocatedUnfairLock(initialState: State())
  }

  /// The first record for a key is written to disk, whole file, synchronously. Later ones for the
  /// same key do nothing. A write error is swallowed: it must never reach the Snap path.
  public func noteIfFirst(_ record: RecoveryRecord) {
    session.state.withLock { state in
      guard state.noted.insert(Key(record)).inserted else { return }
      state.records.append(record)
      guard let data = Self.encode(state.records) else { return }
      try? store.saveRaw(data, as: .recovery)
    }
  }

  /// The records still true of a running app: same bundle id, pid and launch date, prior value on.
  /// File order. The file is deleted afterwards; the caller sets Enhanced UI back on for each pid.
  public func restoreAtLaunch(running: [RecoveryRecord]) -> [RecoveryRecord] {
    defer { store.remove(.recovery) }
    guard let data = store.loadRaw(.recovery),
      let saved = try? JSONDecoder().decode([RecoveryRecord].self, from: data)
    else { return [] }
    let live = Set(running.map(Key.init))
    return saved.filter { $0.priorEnhancedUI && live.contains(Key($0)) }
  }

  /// Quit and permission revocation: delete the file and forget the records. The noted set stays,
  /// so an app already handled this session is not written again. Idempotent.
  public func drainAndDelete() {
    session.state.withLock { $0.records = [] }
    store.remove(.recovery)
  }

  private static func encode(_ records: [RecoveryRecord]) -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try? encoder.encode(records)
  }
}
