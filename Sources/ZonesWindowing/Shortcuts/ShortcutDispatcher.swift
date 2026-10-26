import Foundation
import ZonesCore

public enum ShortcutDispatcher {
  /// Window commands pressed while a Drag Session is live are dropped with one log line (AC-110).
  /// `openEditor` and `openSettings` are not window commands and always pass.
  public static func dispatch(_ a: ShortcutAction, reducerIdle: Bool) -> Result<ShortcutAction, NoOpReason> {
    guard a.isWindowAction, !reducerIdle else { return .success(a) }
    Log.shared.event(
      LogEvent(
        time: ProcessInfo.processInfo.systemUptime, category: .shortcuts, level: .info,
        message: "shortcut dropped: " + NoOpReason.notIdle.rawValue))
    return .failure(.notIdle)
  }
}
