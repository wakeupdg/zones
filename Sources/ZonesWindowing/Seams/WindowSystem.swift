import CoreGraphics
import Foundation
import ZonesCore

public enum AXNotice: Hashable, Sendable {
  case destroyed(WindowKey), appTerminated(pid_t), moved(WindowKey), apiDisabled
}

/// Accessibility. Production: AXWindowSystem. Fake: FakeWindowSystem.
public protocol WindowSystem: Sendable {
  @WindowActor func setTimeouts(perApp: TimeInterval, processWide: TimeInterval)
  @WindowActor func element(at point: CGPoint) -> WindowHandle?
  @WindowActor func windows(of pid: pid_t) -> [WindowHandle]
  @WindowActor func focusedWindow() -> WindowHandle?
  @WindowActor func frame(_ h: WindowHandle) -> AXRead<CGRect>
  @WindowActor func frames(_ hs: [WindowHandle]) -> [WindowKey: AXRead<CGRect>]
  @WindowActor func facts(_ h: WindowHandle) -> AXRead<WindowFacts>
  @WindowActor func setPosition(_ p: CGPoint, _ h: WindowHandle) -> AXStatus
  @WindowActor func setSize(_ s: CGSize, _ h: WindowHandle) -> AXStatus
  @WindowActor func enhancedUI(pid: pid_t) -> AXRead<Bool?>
  @WindowActor func setEnhancedUI(_ on: Bool, pid: pid_t) -> AXStatus
  @WindowActor func trivialRead() -> AXStatus
  func notices() -> AsyncStream<AXNotice>
}
