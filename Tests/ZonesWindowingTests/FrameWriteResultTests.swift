import CoreGraphics
import Testing
import ZonesCore

/// Compile-time guards (AC-159): each switch has no `default`, so a new case breaks the build.
@Suite struct FrameWriteResultTests {
  private func label(_ r: FrameWriteResult) -> String {
    switch r {
    case .applied: "applied"
    case .clamped: "clamped"
    case .refused: "refused"
    case .timedOut: "timedOut"
    case .elementGone: "elementGone"
    case .noOp: "noOp"
    }
  }

  private func label(_ s: AXStatus) -> String {
    switch s {
    case .ok: "ok"
    case .timedOut: "timedOut"
    case .elementGone: "elementGone"
    case .apiDisabled: "apiDisabled"
    case .refused: "refused"
    }
  }

  private func label(_ r: AXRead<CGRect>) -> String {
    switch r {
    case .value: "value"
    case .timedOut: "timedOut"
    case .elementGone: "elementGone"
    case .apiDisabled: "apiDisabled"
    case .refused: "refused"
    }
  }

  @Test func exhaustiveSwitch() {
    let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
    let results: [FrameWriteResult] = [
      .applied(rect), .clamped(rect), .refused(-1), .timedOut, .elementGone, .noOp(.sameFrame),
    ]
    #expect(Set(results.map(label)).count == 6)
    let statuses: [AXStatus] = [.ok, .timedOut, .elementGone, .apiDisabled, .refused(-1)]
    #expect(Set(statuses.map(label)).count == 5)
    let reads: [AXRead<CGRect>] = [.value(rect), .timedOut, .elementGone, .apiDisabled, .refused(-1)]
    #expect(Set(reads.map(label)).count == 5)
  }
}
