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
    switch event.level {
    case .debug: logger.debug("\(event.message, privacy: .public)")
    case .info: logger.info("\(event.message, privacy: .public)")
    case .notice: logger.notice("\(event.message, privacy: .public)")
    case .error: logger.error("\(event.message, privacy: .public)")
    }
  }
}
