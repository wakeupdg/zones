import ApplicationServices
import Foundation

// MARK: - AXStatus (private local copy of docs/CONTRACTS.md 3.0 so T13/T20 can lift it)

enum AXStatus: Hashable, Sendable {
  case ok, timedOut, elementGone, apiDisabled
  case refused(Int32)

  /// Maps a raw AXError rawValue. apiDisabled = -25211, invalidUIElement = -25202.
  init(raw: Int32) {
    switch raw {
    case 0: self = .ok
    case -25211: self = .apiDisabled
    case -25202: self = .elementGone
    default: self = .refused(raw)
    }
  }

  var name: String {
    switch self {
    case .ok: "ok"
    case .timedOut: "timedOut"
    case .elementGone: "elementGone"
    case .apiDisabled: "apiDisabled"
    case .refused(let raw): "refused(\(raw))"
    }
  }
}

/// Raw AXError name for the log (finer than AXStatus).
func rawAXErrorName(_ raw: Int32) -> String {
  switch raw {
  case 0: "success"
  case -25200: "failure"
  case -25201: "illegalArgument"
  case -25202: "invalidUIElement"
  case -25203: "invalidUIElementObserver"
  case -25204: "cannotComplete"
  case -25205: "attributeUnsupported"
  case -25206: "actionUnsupported"
  case -25207: "notificationUnsupported"
  case -25208: "notImplemented"
  case -25209: "notificationAlreadyRegistered"
  case -25210: "notificationNotRegistered"
  case -25211: "apiDisabled"
  case -25212: "noValue"
  case -25213: "parameterizedAttributeUnsupported"
  case -25214: "notEnoughPrecision"
  default: "unknown"
  }
}

// MARK: - Interval statistics

struct SeriesStats: Equatable {
  var count: Int
  var min: Double
  var median: Double
  var max: Double
}

func seriesStats(_ values: [Double]) -> SeriesStats? {
  guard !values.isEmpty else { return nil }
  let s = values.sorted()
  let mid = s.count / 2
  let median = s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
  return SeriesStats(count: s.count, min: s[0], median: median, max: s[s.count - 1])
}

/// Inter-arrival gaps in milliseconds from ascending timestamps in seconds.
func interArrivalMs(_ times: [Double]) -> [Double] {
  guard times.count > 1 else { return [] }
  return zip(times.dropFirst(), times).map { ($0 - $1) * 1000 }
}

// MARK: - Clock and JSON-lines logger

/// Seconds since boot, the `t` field of every log line.
func now() -> Double { ProcessInfo.processInfo.systemUptime }

/// Spike-only: all mutable state sits behind the lock, so @unchecked Sendable is sound.
final class JSONLog: @unchecked Sendable {
  private let lock = NSLock()
  private let start = now()
  private var handle: FileHandle?
  private(set) var path: String?

  /// Opens docs/spikes/logs/<mode>-<app>-<run>.jsonl, found by walking up from the cwd.
  func open(mode: String, app: String) {
    lock.lock()
    defer { lock.unlock() }
    let fm = FileManager.default
    var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
    var logs: URL?
    for _ in 0..<8 {
      let candidate = dir.appendingPathComponent("docs/spikes")
      if fm.fileExists(atPath: candidate.path) {
        logs = candidate.appendingPathComponent("logs")
        break
      }
      dir.deleteLastPathComponent()
    }
    let base = logs ?? URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("logs")
    try? fm.createDirectory(at: base, withIntermediateDirectories: true)
    let prefix = "\(mode)-\(app)-"
    let existing = (try? fm.contentsOfDirectory(atPath: base.path))?.filter { $0.hasPrefix(prefix) }.count ?? 0
    let file = base.appendingPathComponent("\(prefix)\(existing + 1).jsonl")
    fm.createFile(atPath: file.path, contents: nil)
    handle = try? FileHandle(forWritingTo: file)
    path = file.path
  }

  /// One JSON object per line to stdout and to the log file. `t` is seconds since start.
  func emit(_ fields: [String: Any]) {
    var obj = fields
    lock.lock()
    defer { lock.unlock() }
    obj["t"] = Decimal(string: String(format: "%.3f", now() - start)) ?? 0
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
      var line = String(data: data, encoding: .utf8)
    else { return }
    line += "\n"
    FileHandle.standardOutput.write(Data(line.utf8))
    handle?.write(Data(line.utf8))
  }
}

let probeLog = JSONLog()  // spike-only global; JSONLog is internally locked (@unchecked Sendable)

// MARK: - Args

func argValue(_ name: String, in args: [String]) -> String? {
  guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
  return args[i + 1]
}

func fail(_ message: String, code: Int32) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(code)
}
