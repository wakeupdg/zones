import ApplicationServices
import Testing
import ZonesCore

@testable import ZonesWindowing

@Suite struct AXObserverBridgeTests {
  private func next(_ it: inout AsyncStream<AXNotice>.Iterator) async -> AXNotice? { await it.next() }

  @Test func fanOut() async {
    let bridge = AXObserverBridge()
    let key = WindowKey(pid: 7, elementHash: 99)
    var a = bridge.notices().makeAsyncIterator()
    var b = bridge.notices().makeAsyncIterator()
    bridge.emit(.destroyed(key))
    bridge.emit(.appTerminated(42))
    #expect(await next(&a) == .destroyed(key))
    #expect(await next(&a) == .appTerminated(42))
    #expect(await next(&b) == .destroyed(key))
    #expect(await next(&b) == .appTerminated(42))

    // A stream created after an emit does not replay it.
    var late = bridge.notices().makeAsyncIterator()
    bridge.emit(.appTerminated(43))
    #expect(await next(&late) == .appTerminated(43))
    #expect(await next(&a) == .appTerminated(43))
  }

  /// Needs no Accessibility grant: untrusted or unsupported registrations are dropped quietly. The live callbacks
  /// (SPK-013) cannot run under `swift test`.
  @Test func watchIsSafeAndIdempotent() {
    let pid = getpid()
    let handle = WindowHandle(element: AXUIElementCreateApplication(pid), pid: pid)
    let bridge = AXObserverBridge()
    bridge.watch(handle)
    bridge.watch(handle)
    bridge.stop(pid: pid)
    bridge.watch(handle)
  }
}
