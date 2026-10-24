import ApplicationServices
import Foundation
import ZonesCore
import os

/// The `AsyncStream<AXNotice>` fan-out. Safe to call from any thread, including the observer thread.
final class NoticeHub: Sendable {
  private struct State {
    var continuations: [UUID: AsyncStream<AXNotice>.Continuation] = [:]
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

  /// A new stream per call. It sees only notices emitted after this call.
  func stream() -> AsyncStream<AXNotice> {
    let id = UUID()
    let (stream, continuation) = AsyncStream<AXNotice>.makeStream()
    state.withLock { $0.continuations[id] = continuation }
    continuation.onTermination = { [state] _ in
      state.withLock { _ = $0.continuations.removeValue(forKey: id) }
    }
    return stream
  }

  func emit(_ notice: AXNotice) {
    let targets = state.withLock { Array($0.continuations.values) }
    for continuation in targets { continuation.yield(notice) }
  }

  func finishAll() {
    let targets = state.withLock { s -> [AsyncStream<AXNotice>.Continuation] in
      let all = Array(s.continuations.values)
      s.continuations.removeAll()
      return all
    }
    for continuation in targets { continuation.finish() }
  }
}

/// Hosts `AXObserver`s on one dedicated thread (SPK-013) and feeds `notices()` with `destroyed` and
/// `appTerminated`. `moved` and `apiDisabled` are not emitted by this ticket.
public final class AXObserverBridge: Sendable {
  private let hub = NoticeHub()

  public init() {}

  deinit { hub.finishAll() }

  /// A new stream per call; continuations live behind a lock, so this is callable from any context.
  public nonisolated func notices() -> AsyncStream<AXNotice> { hub.stream() }

  /// Drives the stream. Internal so tests can inject notices.
  func emit(_ notice: AXNotice) { hub.emit(notice) }
}
