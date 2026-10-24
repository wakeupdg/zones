import Foundation

// PanelProbe: throwaway spike for T03 (SPK-002, SPK-009, SPK-001). Not part of the Zones packages.

// MARK: - Pure helpers (covered by --self-test)

struct Stats {
  let sorted: [Double]
  init(samples: [Double]) { sorted = samples.sorted() }
  var count: Int { sorted.count }
  /// Nearest-rank percentile, q in 0...1.
  func percentile(_ q: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    let rank = Swift.max(1, Int((q * Double(sorted.count)).rounded(.up)))
    return sorted[Swift.min(rank, sorted.count) - 1]
  }
  var p50: Double { percentile(0.50) }
  var p95: Double { percentile(0.95) }
  var p99: Double { percentile(0.99) }
  var max: Double { sorted.last ?? .nan }
  /// Fraction of samples strictly above `limit`.
  func shareOver(_ limit: Double) -> Double {
    guard !sorted.isEmpty else { return .nan }
    return Double(sorted.filter { $0 > limit }.count) / Double(sorted.count)
  }
}

func markdownTable(header: [String], rows: [[String]]) -> String {
  var out = "| " + header.joined(separator: " | ") + " |\n"
  out += "| " + header.map { _ in "---" }.joined(separator: " | ") + " |\n"
  for r in rows { out += "| " + r.joined(separator: " | ") + " |\n" }
  return out
}

func selfTest() -> Bool {
  var failures = 0
  func check(_ ok: Bool, _ name: String) {
    if !ok { failures += 1; print("FAIL \(name)") } else { print("ok   \(name)") }
  }
  let samples = (1...100).map { Double($0) / 10.0 }  // 0.1 ... 10.0 ms
  let s = Stats(samples: samples)
  check(abs(s.p50 - 5.0) < 1e-9, "p50")
  check(abs(s.p95 - 9.5) < 1e-9, "p95")
  check(abs(s.p99 - 9.9) < 1e-9, "p99")
  check(abs(s.max - 10.0) < 1e-9, "max")
  check(abs(s.shareOver(8.33) - 0.17) < 1e-9, "shareOver8.33")
  let t = markdownTable(header: ["a", "b"], rows: [["1", "2"], ["3", "4"]])
  check(t == "| a | b |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n", "table")
  return failures == 0
}

let args = CommandLine.arguments.dropFirst()
if args.first == "--self-test" { exit(selfTest() ? 0 : 1) }
print("usage: PanelProbe --self-test | panel | frametime | witness")
