import CoreGraphics
import Foundation
import ZonesCore

/// Where each window was before Zones first moved it, plus the last applied Snap (ADR-0009 amended).
/// A plain value: no Clock, no Task, no timer, so nothing sweeps it. Entries leave only through
/// `forget`, `evict(pid:)` or a destroyed / app-terminated notice.
public struct OriginalFrameRegistry: Hashable, Sendable {
  private var entries: [WindowKey: OriginalFrameEntry] = [:]
  private var snaps: [WindowKey: LastSnapRecord] = [:]

  public init() {}

  /// Stores the entry unless one exists for that window. Returns false, and changes nothing, when it does.
  public mutating func capture(_ e: OriginalFrameEntry) -> Bool {
    guard entries[e.key] == nil else { return false }
    entries[e.key] = e
    return true
  }

  /// A single-Zone Snap and a Span Snap record the same kind of entry. The Original Frame is untouched.
  public mutating func recordSnap(_ r: LastSnapRecord) { snaps[r.key] = r }

  public func entry(_ k: WindowKey) -> OriginalFrameEntry? { entries[k] }
  public func lastSnap(_ k: WindowKey) -> LastSnapRecord? { snaps[k] }

  /// Drops the Original Frame and the last-Snap record of one window.
  public mutating func forget(_ k: WindowKey) {
    entries[k] = nil
    snaps[k] = nil
  }

  /// Drops every entry and last-Snap record of one process.
  public mutating func evict(pid: pid_t) {
    entries = entries.filter { $0.key.pid != pid }
    snaps = snaps.filter { $0.key.pid != pid }
  }

  /// `destroyed` forgets that window, `appTerminated` evicts the pid. `moved` and `apiDisabled` are
  /// bookkeeping only (ADR-0006) and change nothing.
  public mutating func apply(_ n: AXNotice) {
    switch n {
    case .destroyed(let key): forget(key)
    case .appTerminated(let pid): evict(pid: pid)
    case .moved, .apiDisabled: break
    }
  }
}
