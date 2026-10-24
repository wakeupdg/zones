import CoreFoundation
import Foundation

/// The dedicated `ax-observer` thread shared by `thread` and `cadence` modes.
/// The thread owns a run loop with a custom source (no keepalive timer). Extra sources
/// (an AXObserver source) are added by `setup`, which runs on the thread before CFRunLoopRun.
/// Spike-only: all mutable state is behind `lock`, so @unchecked Sendable is sound.
final class ObserverThread: @unchecked Sendable {
  static let threadName = "ax-observer"

  struct Callback: Sendable {
    var source: String
    var detail: String
    var onObserverThread: Bool
    var onMain: Bool
    var threadName: String
    var t: Double
  }

  private let lock = NSLock()
  private var thread: Thread?
  private var observerPthread: pthread_t?
  private var runLoop: CFRunLoop?
  private var customSource: CFRunLoopSource?
  private var callbacks: [Callback] = []
  private var runLoopReturned = false
  private var stopRequested = false

  /// Starts the thread and blocks until its run loop is live. `setup` runs on the thread.
  func start(setup: @escaping @Sendable () -> Void = {}) {
    let ready = DispatchSemaphore(value: 0)
    let th = Thread { [self] in
      lock.lock()
      observerPthread = pthread_self()
      runLoop = CFRunLoopGetCurrent()
      lock.unlock()

      var ctx = CFRunLoopSourceContext(
        version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
        retain: nil, release: nil, copyDescription: nil, equal: nil, hash: nil,
        schedule: nil, cancel: nil,
        perform: { info in
          guard let info else { return }
          Unmanaged<ObserverThread>.fromOpaque(info).takeUnretainedValue()
            .noteCallback(source: "custom", detail: "")
        })
      let src = CFRunLoopSourceCreate(nil, 0, &ctx)
      CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)
      lock.lock()
      customSource = src
      lock.unlock()
      setup()
      ready.signal()

      CFRunLoopRun()  // no keepalive timer: must stay alive on the sources alone

      lock.lock()
      runLoopReturned = true
      let expected = stopRequested
      lock.unlock()
      probeLog.emit(["event": "runLoopReturned", "expected": expected])
    }
    th.name = Self.threadName
    lock.lock()
    thread = th
    lock.unlock()
    th.start()
    ready.wait()
  }

  /// Signals the custom source from the calling thread (typically main).
  func signalCustom() {
    lock.lock()
    let src = customSource
    let rl = runLoop
    lock.unlock()
    guard let src, let rl else { return }
    CFRunLoopSourceSignal(src)
    CFRunLoopWakeUp(rl)
  }

  func stop() {
    lock.lock()
    stopRequested = true
    let rl = runLoop
    lock.unlock()
    if let rl { CFRunLoopStop(rl) }
  }

  /// True while the run loop has not returned (before stop was requested).
  var returnedEarly: Bool {
    lock.lock()
    defer { lock.unlock() }
    return runLoopReturned && !stopRequested
  }

  var recorded: [Callback] {
    lock.lock()
    defer { lock.unlock() }
    return callbacks
  }

  /// Called from any callback (custom source or AXObserver) to record which thread ran it.
  func noteCallback(source: String, detail: String) {
    lock.lock()
    let onObserver = observerPthread.map { pthread_equal(pthread_self(), $0) != 0 } ?? false
    lock.unlock()
    let rec = Callback(
      source: source, detail: detail, onObserverThread: onObserver,
      onMain: pthread_main_np() != 0, threadName: Thread.current.name ?? "", t: now())
    lock.lock()
    callbacks.append(rec)
    lock.unlock()
    probeLog.emit([
      "event": "callback", "source": source, "detail": detail,
      "onAxObserverThread": rec.onObserverThread, "onMain": rec.onMain,
      "threadName": rec.threadName,
    ])
  }
}
