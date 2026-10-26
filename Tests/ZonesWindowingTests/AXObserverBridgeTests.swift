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

  /// T64: AX keeps a subscription's refcon after `forget`, so the box must live until the pid's observer goes. A
  /// second destroyed callback for the same refcon is ignored instead of reading freed memory.
  @Test func forgottenBoxLivesUntilTheObserverGoes() async throws {
    let hub = NoticeHub()
    let table = ObserverTable(hub: hub)
    let pid = getpid()
    let key = WindowKey(pid: pid, elementHash: 99)
    let observer = try #require(table.observer(for: pid))
    var notices = hub.stream().makeAsyncIterator()
    weak var weakBox: SubscriptionBox?
    let refcon: UnsafeMutableRawPointer
    do {
      let box = SubscriptionBox(key: key, hub: hub, table: table)
      weakBox = box
      refcon = Unmanaged.passUnretained(box).toOpaque()
      table.record(.success, box, pid: pid)
    }
    #expect(weakBox != nil)

    let element = AXUIElementCreateApplication(pid)
    let name = kAXUIElementDestroyedNotification as CFString
    destroyedCallback(observer, element, name, refcon)  // forgets the key
    #expect(weakBox != nil)  // AX still holds the refcon
    if weakBox != nil { destroyedCallback(observer, element, name, refcon) }  // a duplicate delivery
    hub.emit(.appTerminated(1))
    #expect(await next(&notices) == .destroyed(key))
    #expect(await next(&notices) == .appTerminated(1))

    table.drop(pid: pid)
    #expect(weakBox == nil)
  }
}
