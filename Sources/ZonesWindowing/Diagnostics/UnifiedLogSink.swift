import Foundation
import ZonesCore
import os

/// Production sink: one `os.Logger` per category, subsystem "Zones". Messages never carry window
/// text, so they are logged public.
public final class UnifiedLogSink: LogSink, Sendable {
  public static let subsystem = "Zones"

  private let loggers: [LogCategory: Logger]

  public init() {
    loggers = Dictionary(
      uniqueKeysWithValues: LogCategory.allCases.map {
        ($0, Logger(subsystem: Self.subsystem, category: $0.rawValue))
      })
  }

  public func write(_ event: LogEvent) {
    guard let logger = loggers[event.category] else { return }
    let line = Self.line(for: event)
    switch event.level {
    case .debug: logger.debug("\(line, privacy: .public)")
    case .info: logger.info("\(line, privacy: .public)")
    case .notice: logger.notice("\(line, privacy: .public)")
    case .error: logger.error("\(line, privacy: .public)")
    }
  }

  /// The message plus the app identity the event carries (bundle id, pid), never window text (LI-003).
  public static func line(for event: LogEvent) -> String {
    var line = event.message
    if let bundleID = event.bundleID { line += " bundle=\(bundleID)" }
    if let pid = event.pid { line += " pid=\(pid)" }
    return line
  }
}
