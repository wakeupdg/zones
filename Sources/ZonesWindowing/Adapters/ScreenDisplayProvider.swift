// Manual: AC-119 (SPK-012)
import AppKit
import CoreGraphics
import Foundation
import ZonesCore

/// Production `DisplayProvider` over NSScreen and CoreGraphics. Frames stay in AppKit space.
/// Unstable keys: `nil:<CGDirectDisplayID>` when the UUID cannot be read (retried by the reducer), and
/// `dup:<uuid>#<CGDirectDisplayID>` for each of several attached Displays that report one UUID (never retried).
public final class ScreenDisplayProvider: DisplayProvider, Sendable {
  public init() {}

  public func snapshot() -> TopologySnapshot {
    if Thread.isMainThread { return MainActor.assumeIsolated { Self.read() } }
    return DispatchQueue.main.sync { MainActor.assumeIsolated { Self.read() } }
  }

  public var changes: AsyncStream<RawDisplayChange> {
    AsyncStream { continuation in
      let box = ChangeBox(continuation)
      let info = Unmanaged.passRetained(box).toOpaque()
      CGDisplayRegisterReconfigurationCallback(displayReconfigured, info)
      let observer = ObserverToken(
        NotificationCenter.default.addObserver(
          forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil
        ) { _ in continuation.yield(.screenParameters) })
      continuation.onTermination = { _ in
        CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(box).toOpaque())
        Unmanaged.passUnretained(box).release()
        NotificationCenter.default.removeObserver(observer.token)
      }
    }
  }

  @MainActor
  private static func read() -> TopologySnapshot {
    struct Entry {
      var screen: NSScreen
      var id: CGDirectDisplayID
      var uuid: String?
    }
    let entries: [Entry] = NSScreen.screens.compactMap { screen in
      guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      else { return nil }
      let id = CGDirectDisplayID(truncating: number)
      return Entry(screen: screen, id: id, uuid: uuidString(for: id))
    }
    var uuidCounts: [String: Int] = [:]
    for entry in entries { if let uuid = entry.uuid { uuidCounts[uuid, default: 0] += 1 } }

    func key(_ entry: Entry) -> DisplayKey {
      guard let uuid = entry.uuid else { return .unstable("nil:\(entry.id)") }
      return uuidCounts[uuid, default: 0] > 1 ? .unstable("dup:\(uuid)#\(entry.id)") : .uuid(uuid)
    }
    let keysByID = Dictionary(entries.map { ($0.id, key($0)) }, uniquingKeysWith: { first, _ in first })

    let displays = entries.enumerated().map { index, entry -> DisplaySnapshot in
      let screen = entry.screen
      let scale = Double(screen.backingScaleFactor)
      let master = CGDisplayMirrorsDisplay(entry.id)
      return DisplaySnapshot(
        key: key(entry), frame: screen.frame, visibleFrame: screen.visibleFrame, scale: scale,
        // The menu-bar Display is screens[0]; NSScreen.main follows keyboard focus.
        isMain: index == 0, mirrorOf: master == 0 ? nil : keysByID[master], name: screen.localizedName,
        resolution: pixelSize(of: entry.id) ?? CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale))
    }
    return TopologySnapshot(
      displays: displays, separateSpaces: NSScreen.screensHaveSeparateSpaces,
      primaryFrame: NSScreen.screens.first?.frame ?? .zero)
  }

  private static func uuidString(for id: CGDirectDisplayID) -> String? {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
      let text = CFUUIDCreateString(nil, uuid)
    else { return nil }
    return (text as String).uppercased()
  }

  private static func pixelSize(of id: CGDirectDisplayID) -> CGSize? {
    guard let mode = CGDisplayCopyDisplayMode(id), mode.pixelWidth > 0, mode.pixelHeight > 0 else { return nil }
    return CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
  }
}

private final class ChangeBox: Sendable {
  let continuation: AsyncStream<RawDisplayChange>.Continuation
  init(_ continuation: AsyncStream<RawDisplayChange>.Continuation) { self.continuation = continuation }
}

/// Only `removeObserver` is ever called on the token, and NotificationCenter allows that from any thread.
private final class ObserverToken: @unchecked Sendable {
  let token: any NSObjectProtocol
  init(_ token: any NSObjectProtocol) { self.token = token }
}

/// CoreGraphics calls this twice per change: once with `beginConfigurationFlag` (ignored, and nothing may
/// reconfigure inside it), then when the new configuration is in place.
private func displayReconfigured(
  _ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ info: UnsafeMutableRawPointer?
) {
  guard !flags.contains(.beginConfigurationFlag), let info else { return }
  Unmanaged<ChangeBox>.fromOpaque(info).takeUnretainedValue().continuation.yield(.reconfiguration)
}
