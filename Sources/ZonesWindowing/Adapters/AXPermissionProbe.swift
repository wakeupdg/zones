import AppKit
import ApplicationServices
import Foundation

/// Accessibility is the only permission Zones asks for (ADR-0020). Never prompts (ADR-0021 amendment).
public struct AXPermissionProbe: PermissionProbe {
  public static let settingsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

  public let launchedAtLogin: Bool

  /// Pass `nil` to read the launch Apple event once. Construct inside `applicationDidFinishLaunching`, where
  /// that event is still current.
  public init(launchedAtLogin: Bool? = nil) {
    self.launchedAtLogin = launchedAtLogin ?? Self.launchedAsLoginItem()
  }

  /// Asked every time; the answer is never cached (revocation can happen at any moment).
  public func isTrusted() -> Bool { AXIsProcessTrusted() }

  @MainActor public func openAccessibilitySettings() {
    NSWorkspace.shared.open(Self.settingsURL)
  }

  private static func launchedAsLoginItem() -> Bool {
    let event = NSAppleEventManager.shared().currentAppleEvent
    let value = event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
    return value == AEKeyword(keyAELaunchedAsLogInItem)
  }
}
