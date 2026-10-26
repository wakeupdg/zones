import CoreGraphics
import Foundation
import ZonesCore

/// CoreGraphics window list. Production: CGWindowEnumerator. Fake: FakeWindowEnumerator.
public protocol WindowEnumerator: Sendable {
  func onScreenWindows() -> [WindowRef]
  func windows(ids: [WindowID]) -> [WindowRef]
  func candidates(under point: CGPoint, hint: WindowID?) -> [WindowRef]
}
