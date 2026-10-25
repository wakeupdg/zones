import AppKit
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
/// hashed (CFHash on a dead element is meaningless). AX holds it unretained, so the table keeps it until the pid's
/// observer goes, even after `forget`.
final class SubscriptionBox {
  let key: WindowKey
  let hub: NoticeHub
  weak var table: ObserverTable?
  private var fired = false

  init(key: WindowKey, hub: NoticeHub, table: ObserverTable) {
    self.key = key
    self.hub = hub
    self.table = table
  }

  /// True the first time only, so a repeated destroyed notification emits nothing. Observer thread only.
  func fire() -> Bool {
    defer { fired = true }
    return !fired
  }
}

let destroyedCallback: AXObserverCallback = { _, _, _, refcon in
  guard let refcon else { return }
  let box = Unmanaged<SubscriptionBox>.fromOpaque(refcon).takeUnretainedValue()
  guard box.fire() else { return }
  box.hub.emit(.destroyed(box.key))
  box.table?.forget(box.key, pid: box.key.pid)
}

/// Observers and their subscriptions. Touched only on the observer thread.
final class ObserverTable {
  private struct Entry {
    var observer: AXObserver
    var boxes: [WindowKey: SubscriptionBox] = [:]
    /// Forgotten boxes whose refcon AX may still hold; released with the observer (one small box per destroyed window).
    var retired: [SubscriptionBox] = []
  }

  private var entries: [pid_t: Entry] = [:]
  private let hub: NoticeHub

  init(hub: NoticeHub) { self.hub = hub }

  func subscribe(_ handle: WindowHandle) {
    let key = handle.key
    guard let observer = observer(for: handle.pid) else {
      hub.unwatch(key)
      return
    }
    let box = SubscriptionBox(key: key, hub: hub, table: self)
    let code = AXObserverAddNotification(
      observer, handle.element, kAXUIElementDestroyedNotification as CFString,
      Unmanaged.passUnretained(box).toOpaque())
    record(code, box, pid: handle.pid)
  }

  /// Files the result of one `AXObserverAddNotification`. Internal so tests can drive it without a live
  /// registration; the pid's observer must exist.
  func record(_ code: AXError, _ box: SubscriptionBox, pid: pid_t) {
    switch code {
    case .success:
      if let old = entries[pid]?.boxes.updateValue(box, forKey: box.key) { entries[pid]?.retired.append(old) }
    case .notificationAlreadyRegistered:
      break  // an equivalent subscription exists; its box is already in the table
    default:
      hub.unwatch(box.key)  // element gone, app hung or API disabled: a later handle may retry
    }
  }

  /// The box moves to `retired`, not away: its AX registration and refcon stay until the observer is dropped.
  func forget(_ key: WindowKey, pid: pid_t) {
    if let box = entries[pid]?.boxes.removeValue(forKey: key) { entries[pid]?.retired.append(box) }
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

  /// The pid's observer, created and added to this thread's run loop on first use. Internal for tests.
  func observer(for pid: pid_t) -> AXObserver? {
    if let existing = entries[pid] { return existing.observer }
    var observer: AXObserver?
    guard AXObserverCreate(pid, destroyedCallback, &observer) == .success, let observer else { return nil }
    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
    entries[pid] = Entry(observer: observer)
    return observer
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

  private let terminationToken = OSAllocatedUnfairLock<NSObjectProtocol?>(uncheckedState: nil)

  public init() { host = ObserverHost(hub: hub) }

  deinit {
    if let token = terminationToken.withLockUnchecked({ $0 }) {
      NSWorkspace.shared.notificationCenter.removeObserver(token)
    }
    hub.finishAll()
  }

  /// A new stream per call; continuations live behind a lock, so this is callable from any context.
  /// The first call also starts the `NSWorkspace` termination feed.
  public nonisolated func notices() -> AsyncStream<AXNotice> {
    startTerminationFeed()
    return hub.stream()
  }

  /// `appTerminated(pid)` from `NSWorkspace.didTerminateApplicationNotification`; also drops that pid's observer.
  private func startTerminationFeed() {
    terminationToken.withLockUnchecked { token in
      guard token == nil else { return }
      token = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil
      ) { [hub, host] note in
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let pid = app.processIdentifier
        hub.unwatch(pid: pid)
        hub.emit(.appTerminated(pid))
        host.performIfStarted { $0.drop(pid: pid) }
      }
    }
  }

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
