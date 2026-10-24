import ApplicationServices
import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

/// AC-163: each seam fake has a response queue, a typed call log and fake-Clock latency.
@Suite struct FakeContractTests {
  /// A handle over a real application element. `pid` picks which one, so two handles can differ.
  static func handle(pid: pid_t = getpid()) -> WindowHandle {
    WindowHandle(element: AXUIElementCreateApplication(pid), pid: pid)
  }

  @Test @WindowActor func windowSystem() {
    let clock = FakeClock()
    let ws = FakeWindowSystem(clock: clock)
    let h = Self.handle()
    let rect = CGRect(x: 10, y: 20, width: 300, height: 200)

    // Queue: FIFO, then the documented default; the call log records every call in order.
    ws.enqueue(.frame(.value(rect)))
    ws.enqueue(.frame(.timedOut))
    #expect(ws.frame(h) == .value(rect))
    #expect(ws.frame(h) == .timedOut)
    #expect(ws.frame(h) == .elementGone)
    #expect(ws.calls == [.frame(h), .frame(h), .frame(h)])

    // Other methods draw from their own kind of response.
    ws.enqueue(.position(.refused(7)))
    ws.enqueue(.size(.timedOut))
    #expect(ws.setPosition(CGPoint(x: 1, y: 2), h) == .refused(7))
    #expect(ws.setSize(CGSize(width: 3, height: 4), h) == .timedOut)
    #expect(ws.setPosition(CGPoint(x: 1, y: 2), h) == .ok)
    #expect(ws.calls.last == .setPosition(CGPoint(x: 1, y: 2), h))

    // ADR-0015 amendment: two consecutive timeouts against the same app can be scripted.
    ws.reset()
    ws.enqueue(.position(.timedOut))
    ws.enqueue(.position(.timedOut))
    #expect(ws.setPosition(.zero, h) == .timedOut)
    #expect(ws.setPosition(.zero, h) == .timedOut)

    // reset() empties the queue and the log.
    ws.enqueue(.frame(.value(rect)))
    ws.reset()
    #expect(ws.calls.isEmpty)
    #expect(ws.frame(h) == .elementGone)

    // Latency 2: nothing completes at 1 s, the call completes at 2 s.
    ws.reset()
    ws.latency = 2
    _ = ws.frame(h)
    #expect(ws.calls == [.frame(h)])
    #expect(ws.completed.isEmpty)
    #expect(ws.inFlight == 1)
    clock.advance(by: 1)
    #expect(ws.completed.isEmpty)
    clock.advance(by: 1)
    #expect(ws.completed == [.frame(h)])
    #expect(ws.inFlight == 0)
  }
}
