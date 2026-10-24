import ApplicationServices
import CoreGraphics
import Foundation

/// Listen-only session tap on the main run loop (ADR-0020: listen-only needs only Accessibility).
/// Spike-only: `onEvent` is set at init and the counters are lock-guarded.
final class ListenOnlyTap: @unchecked Sendable {
  private let lock = NSLock()
  private var port: CFMachPort?
  private var count = 0
  private let onEvent: @Sendable (CGEventType) -> Void

  /// Returns nil from `install()` when the tap cannot be created (the `tapNil` path).
  init(onEvent: @escaping @Sendable (CGEventType) -> Void) { self.onEvent = onEvent }

  func install(types: [CGEventType]) -> Bool {
    var mask: CGEventMask = 0
    for t in types { mask |= CGEventMask(1) << CGEventMask(t.rawValue) }
    guard
      let p = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
        eventsOfInterest: mask,
        callback: { _, type, event, info in
          if let info { Unmanaged<ListenOnlyTap>.fromOpaque(info).takeUnretainedValue().handle(type) }
          return Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else { return false }
    let src = CFMachPortCreateRunLoopSource(nil, p, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
    CGEvent.tapEnable(tap: p, enable: true)
    lock.lock()
    port = p
    lock.unlock()
    return true
  }

  private func handle(_ type: CGEventType) {
    lock.lock()
    count += 1
    lock.unlock()
    onEvent(type)
  }

  /// Events delivered since the last call.
  func takeCount() -> Int {
    lock.lock()
    defer { lock.unlock() }
    let c = count
    count = 0
    return c
  }

  var isEnabled: Bool {
    lock.lock()
    let p = port
    lock.unlock()
    return p.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
  }
}
