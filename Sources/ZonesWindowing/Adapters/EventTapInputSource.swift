import CoreGraphics
import Foundation
import ZonesCore

/// Creates the Mach port behind the event tap. `userInfo` is the retained callback box. A nil result is the
/// "no permission" case (ADR-0020), never a crash. Tests inject a maker so no live tap is created.
struct TapMaker: Sendable {
  var make: @Sendable (TapConfig, UnsafeMutableRawPointer) -> CFMachPort?
}

/// Production `InputSource` over a listen-only `CGEvent` tap on its own thread (AC-065).
public final class EventTapInputSource: Sendable {
  public let config: TapConfig
  let tapMaker: TapMaker
  let primaryFrame: @Sendable () -> CGRect

  init(
    config: TapConfig = .production, tapMaker: TapMaker, primaryFrame: @escaping @Sendable () -> CGRect
  ) {
    self.config = config
    self.tapMaker = tapMaker
    self.primaryFrame = primaryFrame
  }

  /// The mask has one bit per `CGEventType` in `config.mask`; nothing else is ever observed.
  static func cgEventMask(for config: TapConfig) -> CGEventMask {
    config.mask.reduce(CGEventMask(0)) { mask, kind in
      mask | (1 << CGEventMask(cgType(for: kind).rawValue))
    }
  }

  static func cgType(for kind: InputKind) -> CGEventType {
    switch kind {
    case .leftDown: .leftMouseDown
    case .leftDragged: .leftMouseDragged
    case .leftUp: .leftMouseUp
    case .flagsChanged: .flagsChanged
    }
  }
}
