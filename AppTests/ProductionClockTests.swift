import Foundation
import Testing
import ZonesCore
import os

@testable import Zones

@Suite struct ProductionClockTests {
  private static func counter() -> OSAllocatedUnfairLock<Int> { OSAllocatedUnfairLock(initialState: 0) }

  private static func wait(until condition: @Sendable () -> Bool, timeout: TimeInterval = 2) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
  }

  @Test func scheduleFiresOnceAndCancelIsIdempotent() async {
    let clock = ProductionClock()
    let once = Self.counter()
    _ = clock.schedule(.healthTick, after: 0.01, repeats: false) { once.withLock { $0 += 1 } }
    await Self.wait(until: { once.withLock { $0 } >= 1 })
    try? await Task.sleep(nanoseconds: 80_000_000)
    #expect(once.withLock { $0 } == 1)

    let many = Self.counter()
    let handle = clock.schedule(.frameSample, after: 0.01, repeats: true) { many.withLock { $0 += 1 } }
    await Self.wait(until: { many.withLock { $0 } >= 3 })
    #expect(many.withLock { $0 } >= 3)
    clock.cancel(handle)
    clock.cancel(handle)
    try? await Task.sleep(nanoseconds: 30_000_000)
    let frozen = many.withLock { $0 }
    try? await Task.sleep(nanoseconds: 80_000_000)
    #expect(many.withLock { $0 } == frozen)
  }

  @Test func cancelBeforeFirstFireNeverFires() async {
    let clock = ProductionClock()
    let fired = Self.counter()
    let handle = clock.schedule(.trustPoll, after: 0.05, repeats: false) { fired.withLock { $0 += 1 } }
    clock.cancel(handle)
    try? await Task.sleep(nanoseconds: 150_000_000)
    #expect(fired.withLock { $0 } == 0)
  }

  @Test func handlesAreUniquePerScheduleAndNowIsMonotonic() {
    let clock = ProductionClock()
    let a = clock.schedule(.healthTick, after: 60, repeats: false) {}
    let b = clock.schedule(.healthTick, after: 60, repeats: false) {}
    #expect(a != b)
    #expect(a.id == .healthTick)
    clock.cancel(a)
    clock.cancel(b)
    var last = clock.now
    for _ in 0..<1000 {
      let next = clock.now
      #expect(next >= last)
      last = next
    }
  }
}
