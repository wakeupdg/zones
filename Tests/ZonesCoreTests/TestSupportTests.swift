import CoreGraphics
import Foundation
import Testing
import os
import ZonesCore
import ZonesTestSupport

// MARK: FakeClock

/// Records the order timers fired in.
private final class Recorder: Sendable {
  private let items = OSAllocatedUnfairLock(initialState: [String]())
  func add(_ s: String) { items.withLock { $0.append(s) } }
  var all: [String] { items.withLock { $0 } }
}

@Test func fakeClockFiresDueTimersInOrder() {
  let clock = FakeClock()
  let log = Recorder()
  _ = clock.schedule(.healthTick, after: 5, repeats: false) { log.add("health") }
  _ = clock.schedule(.trustPoll, after: 1, repeats: false) { log.add("trust") }
  _ = clock.schedule(.deadTapRetry, after: 30, repeats: false) { log.add("dead") }
  #expect(clock.now == 0)
  clock.advance(by: 6)
  #expect(log.all == ["trust", "health"])
  #expect(clock.now == 6)
  #expect(clock.pending == [.deadTapRetry])
  clock.advance(by: 100)
  #expect(log.all == ["trust", "health", "dead"])
  #expect(clock.pending.isEmpty)
}

@Test func fakeClockRepeatsAndCancels() {
  let clock = FakeClock()
  let log = Recorder()
  let repeating = clock.schedule(.frameSample, after: 1, repeats: true) { log.add("tick") }
  clock.advance(by: 3.5)
  #expect(log.all.count == 3)
  #expect(clock.pending == [.frameSample])
  clock.cancel(repeating)
  clock.advance(by: 10)
  #expect(log.all.count == 3)
  #expect(clock.pending.isEmpty)

  let oneShot = clock.schedule(.topologyDebounce, after: 1, repeats: false) { log.add("never") }
  clock.cancel(oneShot)
  clock.advance(by: 5)
  #expect(!log.all.contains("never"))
}

@Test func fakeClockPendingAndFire() {
  let clock = FakeClock()
  let log = Recorder()
  _ = clock.schedule(.suspectResolve, after: 3, repeats: false) { log.add("suspect") }
  _ = clock.schedule(.relaunchGate, after: 10, repeats: false) { log.add("gate") }
  #expect(clock.pending == [.suspectResolve, .relaunchGate])
  clock.fire(.relaunchGate)
  #expect(log.all == ["gate"])
  #expect(clock.pending == [.suspectResolve])
  #expect(clock.now == 0)
  clock.fire(.relaunchGate)  // nothing pending under that id: no effect
  #expect(log.all == ["gate"])
}

// MARK: Generator

@Test func generatorSameSeedSameSequence() {
  var a = Generator(seed: 42)
  var b = Generator(seed: 42)
  var c = Generator(seed: 43)
  let first = (0..<100).map { _ in a.next() }
  #expect(first == (0..<100).map { _ in b.next() })
  #expect(first != (0..<100).map { _ in c.next() })

  var zero = Generator(seed: 0)
  #expect(zero.next() == 0xE220_A839_7B1D_CDAF)  // reference splitmix64 vector

  var d = Generator(seed: 9)
  var e = Generator(seed: 9)
  #expect(d.layout(maxDepth: 4) == e.layout(maxDepth: 4))
}

private func depth(_ n: SplitNode) -> Int {
  switch n {
  case .leaf: 0
  case .split(_, _, let first, let second): 1 + max(depth(first), depth(second))
  }
}

private func ratios(_ n: SplitNode) -> [Double] {
  switch n {
  case .leaf: []
  case .split(_, let ratio, let first, let second): [ratio] + ratios(first) + ratios(second)
  }
}

@Test func generatorTreeIsAlwaysValid() {
  var sawSplit = false
  for seed in UInt64(0)..<200 {
    for maxDepth in 0...5 {
      var g = Generator(seed: seed)
      let tree = g.tree(maxDepth: maxDepth)
      #expect(depth(tree) <= maxDepth, "\(Generator.failureMessage(seed: seed, layout: g.layout(maxDepth: 0), note: "depth"))")
      for r in ratios(tree) {
        sawSplit = true
        #expect(
          (Constants.minFraction...(1 - Constants.minFraction)).contains(r),
          "seed=\(seed) depth=\(maxDepth) ratio=\(r)")
      }
    }
  }
  #expect(sawSplit)
}

@Test func generatorRangesStayInBounds() {
  var g = Generator(seed: 5)
  for _ in 0..<500 {
    #expect((3...7).contains(g.int(3...7)))
    #expect((0.25...0.75).contains(g.double(0.25...0.75)))
    let bounds = CGRect(x: -600, y: 1080, width: 1080, height: 1920)
    let r = g.rect(in: bounds)
    #expect(bounds.contains(r))
    #expect(r.width > 0 && r.height > 0)
    #expect([1, 2, 3].contains(g.pick([1, 2, 3])))
  }
}

@Test func generatorFailureMessageHasSeed() {
  var g = Generator(seed: 7)
  let layout = g.layout(maxDepth: 2)
  let message = Generator.failureMessage(seed: 7, layout: layout, note: "overlap")
  #expect(message.contains("seed=7"))
  #expect(message.contains("overlap"))
  #expect(message.contains(layout.name))
}

// MARK: Fixtures

@Test func threeDisplaysGeometry() throws {
  let t = Fixtures.threeDisplays
  #expect(t.displays.count == 3)
  let primary = try #require(t.displays.first { $0.isMain })
  #expect(primary.scale == 1)
  #expect(primary.frame == CGRect(x: 0, y: 0, width: 1920, height: 1080))
  #expect(t.primaryFrame == primary.frame)
  #expect(t.displays.filter(\.isMain).count == 1)

  let retina = try #require(t.displays.first { $0.scale == 2 })
  #expect(retina.frame == CGRect(x: -1440, y: 0, width: 1440, height: 900))
  let portrait = try #require(t.displays.first { $0.frame.height > $0.frame.width })
  #expect(portrait.frame == CGRect(x: -600, y: 1080, width: 1080, height: 1920))
  #expect(portrait.scale == 1)

  for d in t.displays {
    #expect(d.frame.contains(d.visibleFrame))
    #expect(d.mirrorOf == nil)
  }
  #expect(Set(t.displays.map(\.key)).count == 3)
}
