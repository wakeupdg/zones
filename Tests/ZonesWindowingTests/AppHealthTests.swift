import Foundation
import Testing
import ZonesCore
import ZonesWindowing

@Suite struct AppHealthTests {
  /// AC-077: unresponsive for 10 s on the Clock, then exactly one attempt.
  @Test func cooldownThenOneRetry() {
    var health = AppHealth()
    let pid: pid_t = 4242

    for round in 0..<2 {
      let start = TimeInterval(round) * 100
      #expect(!health.isUnresponsive(pid, now: start))
      let retry1 = health.consumeRetry(pid, now: start)
      #expect(!retry1)

      health.markUnresponsive(pid, now: start)
      #expect(health.isUnresponsive(pid, now: start + 9.9))
      let retry2 = health.consumeRetry(pid, now: start + 9.9)
      #expect(!retry2)
      #expect(!health.isUnresponsive(pid, now: start + 10))
      let retry3 = health.consumeRetry(pid, now: start + 10)
      #expect(retry3)
      let retry4 = health.consumeRetry(pid, now: start + 10)
      #expect(!retry4)
      let retry5 = health.consumeRetry(pid, now: start + 11)
      #expect(!retry5)
      #expect(!health.isUnresponsive(pid, now: start + 11))
    }
  }

  @Test func otherPidsAreUnaffected() {
    var health = AppHealth()
    health.markUnresponsive(1, now: 0)
    #expect(health.isUnresponsive(1, now: 1))
    #expect(!health.isUnresponsive(2, now: 1))
    let retry6 = health.consumeRetry(2, now: 20)
    #expect(!retry6)
  }
}
