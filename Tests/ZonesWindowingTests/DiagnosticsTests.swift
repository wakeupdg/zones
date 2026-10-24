import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

@Suite struct DiagnosticsTests {
  static func event(_ i: Int, category: LogCategory = .core) -> LogEvent {
    LogEvent(time: Double(i), category: category, level: .info, message: "e\(i)")
  }

  @Test func ringBoundedAndSinks() {
    var ring = EventRing()
    for i in 0..<500 { ring.append(Self.event(i)) }
    #expect(ring.events.count == 200)
    #expect(ring.events.map(\.time) == (300..<500).map(Double.init))

    var small = EventRing(capacity: 3)
    for i in 0..<10 { small.append(Self.event(i)) }
    #expect(small.events.map(\.message) == ["e7", "e8", "e9"])

    let expected: [LogCategory] = [
      .core, .layout, .windowing, .input, .permission, .topology, .snap, .restore, .shortcuts, .overlay,
      .diagnostics, .app,
    ]
    #expect(LogCategory.allCases == expected)

    let log = Log()
    let sink = ArrayLogSink()
    log.install(sink: sink)
    for i in 0..<5 { log.event(Self.event(i)) }
    #expect(sink.events.count == 5)
    #expect(log.ring().events == sink.events)

    let unified = UnifiedLogSink()
    for category in LogCategory.allCases {
      for level in [LogLevel.debug, .info, .notice, .error] {
        unified.write(LogEvent(time: 0, category: category, level: level, message: "probe"))
      }
    }
  }
}
