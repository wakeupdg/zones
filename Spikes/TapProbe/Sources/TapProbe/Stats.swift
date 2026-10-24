import AppKit
import CoreGraphics
import Foundation

/// The 120 Hz frame budget from SPK-003: one frame = 8.33 ms.
let frameBudgetMs = 1000.0 / 120.0

struct Distribution {
  var count = 0, p50 = 0.0, p99 = 0.0, max = 0.0

  init(_ values: [Double]) {
    guard !values.isEmpty else { return }
    let sorted = values.sorted()
    count = sorted.count
    p50 = sorted[Swift.min(sorted.count - 1, sorted.count / 2)]
    p99 = sorted[Swift.min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
    max = sorted.last ?? 0
  }

  var line: String { String(format: "n=%d p50=%.3f p99=%.3f max=%.3f", count, p50, p99, max) }
}

enum Stats {
  /// Our own tap's latency counters from CGGetEventTapList (reset on each call).
  static func ownTapLine() -> String? {
    var count: UInt32 = 0
    guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return nil }
    var list = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
    var filled: UInt32 = 0
    guard CGGetEventTapList(count, &list, &filled) == .success else { return nil }
    let me = getpid()
    guard let info = list.prefix(Int(filled)).first(where: { $0.tappingProcess == me }) else { return nil }
    return String(
      format: "TAPLIST id=%u enabled=%@ listenOnly=%@ minUsec=%.1f avgUsec=%.1f maxUsec=%.1f",
      info.eventTapID, "\(info.enabled)", "\(info.options == .listenOnly)",
      info.minUsecLatency, info.avgUsecLatency, info.maxUsecLatency)
  }

  static func displays() -> String {
    NSScreen.screens.map { "\($0.localizedName)@\($0.maximumFramesPerSecond)Hz" }.joined(separator: ", ")
  }

  /// Mean dragged-event rate across contiguous runs (gaps over 100 ms split runs).
  static func draggedRateHz(_ drags: [Sample]) -> Double? {
    var intervals = [Double]()
    for (a, b) in zip(drags, drags.dropFirst()) {
      let dt = b.time - a.time
      if dt > 0, dt < 0.1 { intervals.append(dt) }
    }
    guard !intervals.isEmpty else { return nil }
    return Double(intervals.count) / intervals.reduce(0, +)
  }

  static func summary(_ samples: [Sample], tapLines: [String], seconds: Double) -> [String] {
    var out = ["SUMMARY seconds=\(String(format: "%.1f", seconds)) displays=[\(displays())]"]
    for kind in InputKind.allCases {
      let of = samples.filter { $0.kind == kind }
      out.append("SUMMARY kind=\(kind.rawValue) count=\(of.count)")
    }
    let delays = Distribution(samples.map(\.delayMs)), bodies = Distribution(samples.map(\.callbackMs))
    let dragged = samples.filter { $0.kind == .leftDragged }
    let dDelays = Distribution(dragged.map(\.delayMs)), dBodies = Distribution(dragged.map(\.callbackMs))
    out.append("SUMMARY all-events delayMs \(delays.line)")
    out.append("SUMMARY all-events callbackMs \(bodies.line)")
    out.append("SUMMARY dragged delayMs \(dDelays.line)")
    out.append("SUMMARY dragged callbackMs \(dBodies.line)")
    if let hz = draggedRateHz(dragged) {
      out.append(String(format: "SUMMARY dragged rate=%.1f Hz (runs split on gaps over 100 ms)", hz))
    } else {
      out.append("SUMMARY dragged rate=n/a (fewer than 2 dragged events)")
    }
    let maxCb = bodies.max, maxDelay = delays.max
    let verdict: String
    if samples.isEmpty {
      verdict = "NO-EVENTS"
    } else if dragged.isEmpty {
      verdict = "NO-DRAG-EVENTS (latency not assessable for dragged events)"
    } else {
      verdict = maxCb < frameBudgetMs && maxDelay < frameBudgetMs ? "LATENCY-PASS" : "LATENCY-FAIL"
    }
    out.append(String(format: "SUMMARY budget=%.2fms maxCallback=%.3f maxDelay=%.3f -> %@", frameBudgetMs, maxCb, maxDelay, verdict))
    return out
  }
}
