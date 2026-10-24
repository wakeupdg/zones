import ApplicationServices
import Foundation
import ZonesCore
import os

/// The `AsyncStream<AXNotice>` fan-out. Safe to call from any thread, including the observer thread.
final class NoticeHub: Sendable {
  private struct State {
    var continuations: [UUID: AsyncStream<AXNotice>.Continuation] = [:]
    var watched: Set<WindowKey> = []
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

  /// Records a window as watched; false when it already was, so one subscription exists per key.
  func markWatched(_ key: WindowKey) -> Bool {
    state.withLock { $0.watched.insert(key).inserted }
  }

  func unwatch(_ key: WindowKey) { state.withLock { _ = $0.watched.remove(key) } }

  func unwatch(pid: pid_t) { state.withLock { $0.watched = $0.watched.filter { $0.pid != pid } } }

  func finishAll() {
    let targets = state.withLock { s -> [AsyncStream<AXNotice>.Continuation] in
      let all = Array(s.continuations.values)
      s.continuations.removeAll()
      return all
    }
    for continuation in targets { continuation.finish() }
  }
}

/// The refcon of one destroyed subscription. It carries the key, never the element: a destroyed element must not be
/// hashed (CFHash on a dead element is meaningless).
final class SubscriptionBox {
  let key: WindowKey
  let hub: NoticeHub
  weak var table: ObserverTable?

  init(key: WindowKey, hub: NoticeHub, table: ObserverTable) {
    self.key = key
    self.hub = hub
    self.table = table
  }
}

private let destroyedCallback: AXObserverCallback = { _, _, _, refcon in
  guard let refcon else { return }
  let box = Unmanaged<SubscriptionBox>.fromOpaque(refcon).takeUnretainedValue()
  box.hub.emit(.destroyed(box.key))
  box.table?.forget(box.key, pid: box.key.pid)
}

/// Observers and their subscriptions. Touched only on the observer thread.
final class ObserverTable {
  private struct Entry {
    var observer: AXObserver
    var boxes: [WindowKey: SubscriptionBox] = [:]
  }

  private var entries: [pid_t: Entry] = [:]
  private let hub: NoticeHub

  init(hub: NoticeHub) { self.hub = hub }

  func subscribe(_ handle: WindowHandle) {
    let key = handle.key
    guard var entry = entry(for: handle.pid) else {
      hub.unwatch(key)
      return
    }
    let box = SubscriptionBox(key: key, hub: hub, table: self)
    let code = AXObserverAddNotification(
      entry.observer, handle.element, kAXUIElementDestroyedNotification as CFString,
      Unmanaged.passUnretained(box).toOpaque())
    switch code {
    case .success:
      entry.boxes[key] = box
    case .notificationAlreadyRegistered:
      break  // an equivalent subscription exists; its box is already in the table
    default:
      hub.unwatch(key)  // element gone, app hung or API disabled: a later handle may retry
    }
    entries[handle.pid] = entry
  }

  func forget(_ key: WindowKey, pid: pid_t) {
    entries[pid]?.boxes.removeValue(forKey: key)
    hub.unwatch(key)
  }

  func drop(pid: pid_t) {
    guard let entry = entries.removeValue(forKey: pid) else { return }
    detach(entry.observer)
    hub.unwatch(pid: pid)
  }

  func removeAll() {
    for pid in Array(entries.keys) { drop(pid: pid) }
  }

  private func entry(for pid: pid_t) -> Entry? {
    if let existing = entries[pid] { return existing }
    var observer: AXObserver?
    guard AXObserverCreate(pid, destroyedCallback, &observer) == .success, let observer else { return nil }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    let created = Entry(observer: observer)
    entries[pid] = created
    return created
  }

  private func detach(_ observer: AXObserver) {
    let source = AXObserverGetRunLoopSource(observer)
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
    CFRunLoopSourceInvalidate(source)
  }
}

/// One dedicated thread, started lazily, whose run loop never exits while idle (SPK-013).
final class ObserverHost: Sendable {
  private struct State {
    var runLoop: CFRunLoop?
    var table: ObserverTable?
    var started = false
    var stopped = false
  }

  private let state = OSAllocatedUnfairLock(uncheckedState: State())
  private let ready = DispatchSemaphore(value: 0)
  private let hub: NoticeHub

  init(hub: NoticeHub) { self.hub = hub }

  deinit {
    let runLoop = state.withLockUnchecked { s -> CFRunLoop? in
      s.stopped = true
      return s.runLoop
    }
    if let runLoop {
      CFRunLoopStop(runLoop)
      CFRunLoopWakeUp(runLoop)
    }
  }

  /// Runs `work` on the observer thread, starting it first when needed.
  func perform(_ work: @escaping @Sendable (ObserverTable) -> Void) {
    let runLoop = start()
    CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { [self] in
      guard let table = state.withLockUnchecked({ $0.table }) else { return }
      work(table)
    }
    CFRunLoopWakeUp(runLoop)
  }

  /// Like `perform`, but never starts the thread: with no thread there is nothing to clean up.
  func performIfStarted(_ work: @escaping @Sendable (ObserverTable) -> Void) {
    guard state.withLockUnchecked({ $0.started }) else { return }
    perform(work)
  }

  private func start() -> CFRunLoop {
    let launch = state.withLockUnchecked { s -> Bool in
      if s.started { return false }
      s.started = true
      return true
    }
    if launch { launchThread() }
    ready.wait()
    ready.signal()  // let any other waiter through
    return state.withLockUnchecked { $0.runLoop }!
  }

  private func launchThread() {
    let thread = Thread { [state, ready, hub] in
      let runLoop = CFRunLoopGetCurrent()!
      // A source that never fires keeps the loop alive while idle.
      var context = CFRunLoopSourceContext()
      let keepAlive = CFRunLoopSourceCreate(nil, 0, &context)
      CFRunLoopAddSource(runLoop, keepAlive, .defaultMode)
      let table = ObserverTable(hub: hub)
      state.withLockUnchecked {
        $0.runLoop = runLoop
        $0.table = table
      }
      ready.signal()
      while !state.withLockUnchecked({ $0.stopped }) {
        CFRunLoopRunInMode(.defaultMode, 3600, false)
      }
      table.removeAll()
      state.withLockUnchecked {
        $0.table = nil
        $0.runLoop = nil
      }
    }
    thread.name = "Zones.AXObserver"
    thread.qualityOfService = .userInitiated
    thread.start()
  }
}

/// Hosts `AXObserver`s on one dedicated thread (SPK-013) and feeds `notices()` with `destroyed` and
/// `appTerminated`. `moved` and `apiDisabled` are not emitted by this ticket.
public final class AXObserverBridge: Sendable {
  private let hub = NoticeHub()
  private let host: ObserverHost

  public init() { host = ObserverHost(hub: hub) }

  deinit { hub.finishAll() }

  /// A new stream per call; continuations live behind a lock, so this is callable from any context.
  public nonisolated func notices() -> AsyncStream<AXNotice> { hub.stream() }

  /// Subscribes to the window's destroyed notification. Idempotent per key.
  public func watch(_ handle: WindowHandle) {
    guard hub.markWatched(handle.key) else { return }
    host.perform { $0.subscribe(handle) }
  }

  /// Drops the pid's observer and subscriptions.
  func stop(pid: pid_t) {
    hub.unwatch(pid: pid)
    host.performIfStarted { $0.drop(pid: pid) }
  }

  /// Drives the stream. Internal so tests can inject notices.
  func emit(_ notice: AXNotice) { hub.emit(notice) }
}
