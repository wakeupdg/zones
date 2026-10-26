import ApplicationServices
import Foundation

/// The AX-typed face of `WindowHandle`. Only Adapters import ApplicationServices (AC-162).
extension WindowHandle {
  public convenience init(element: AXUIElement, pid: pid_t) {
    self.init(opaqueElement: element, pid: pid, elementHash: Int(CFHash(element)))
  }

  /// The wrapped element. Always an AXUIElement: the only initializer that takes an element
  /// is the one above.
  public var element: AXUIElement {
    opaqueElement as! AXUIElement  // zones:allow
  }
}
