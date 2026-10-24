import CoreGraphics
import ApplicationServices
import Foundation
import ZonesCore

/// Wraps an AXUIElement. This is the package's only unchecked box (AC-161): the element is
/// immutable, and every call that uses it runs on `WindowActor` (ADR-0015).
public final class WindowHandle: @unchecked Sendable, Hashable {
  public let pid: pid_t
  public var key: WindowKey
  public let element: AXUIElement

  public init(element: AXUIElement, pid: pid_t) {
    self.element = element
    self.pid = pid
    self.key = WindowKey(pid: pid, elementHash: Int(CFHash(element)))
  }

  public static func == (lhs: WindowHandle, rhs: WindowHandle) -> Bool { lhs.key == rhs.key }
  public func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

public struct WindowRecord: Hashable, Sendable {
  public var ref: ZonesCore.WindowRef
  public var handle: WindowHandle
  public var facts: WindowFacts?
  public init(ref: ZonesCore.WindowRef, handle: WindowHandle, facts: WindowFacts?) {
    self.ref = ref
    self.handle = handle
    self.facts = facts
  }
}
