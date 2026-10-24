import Testing
import ZonesCore
import ZonesTestSupport

@Test func failureMessageNamesSeed() {
  var g = Generator(seed: 4242)
  let layout = g.layout(maxDepth: 3)
  let msg = Generator.failureMessage(seed: 4242, layout: layout, note: "marked failing")
  #expect(msg.contains("seed=4242"))
  #expect(msg.contains(String(describing: layout)))
  #expect(msg.contains("marked failing"))

  let big = Generator.failureMessage(seed: UInt64.max, layout: layout, note: "max")
  #expect(big.contains("seed=18446744073709551615"))
}
