import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

@testable import Zones

/// T63: the root installs the adapters' log sink, so `Log.shared` lines (drag exits, skips) reach the unified log.
@MainActor
@Suite struct LogSinkInstallTests {
  @Test func rootInstallsTheLogSink() {
    let h = Harness()
    let sink = ArrayLogSink()
    h.logSink = sink
    _ = h.makeRoot()
    let marker = "T63 sink check \(UUID().uuidString)"
    Log.shared.event(LogEvent(time: 0, category: .input, level: .info, message: marker))
    #expect(sink.events.contains { $0.message == marker })
  }
}
