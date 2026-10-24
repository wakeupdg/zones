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
}
