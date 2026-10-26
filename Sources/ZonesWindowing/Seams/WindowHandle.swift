import CoreGraphics
import Foundation
import ZonesCore

/// Opaque box around a platform window element. This is the package's only unchecked box (AC-161):
/// the element is immutable, and every call that uses it runs on `WindowActor` (ADR-0015).
/// The seam never names the element's type: Adapters/WindowHandle+AX.swift builds a handle from an
/// AXUIElement and reads it back, so `import ApplicationServices` stays under Adapters (AC-162).
public final class WindowHandle: @unchecked Sendable, Hashable {
  public let pid: pid_t
  public var key: WindowKey
  let opaqueElement: AnyObject

  init(opaqueElement: AnyObject, pid: pid_t, elementHash: Int) {
    self.opaqueElement = opaqueElement
    self.pid = pid
    self.key = WindowKey(pid: pid, elementHash: elementHash)
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
