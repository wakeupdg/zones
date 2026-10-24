import CoreGraphics

/// Mirrors the CONTRACTS.md InputKind / TapConfig shape. Single definition of the tap flags and mask (AC-065 analogue).
enum InputKind: String, Hashable, Sendable, CaseIterable {
  case leftDown, leftDragged, leftUp, flagsChanged

  var cgType: CGEventType {
    switch self {
    case .leftDown: .leftMouseDown
    case .leftDragged: .leftMouseDragged
    case .leftUp: .leftMouseUp
    case .flagsChanged: .flagsChanged
    }
  }

  init?(_ type: CGEventType) {
    guard let kind = InputKind.allCases.first(where: { $0.cgType == type }) else { return nil }
    self = kind
  }
}

struct TapConfig: Hashable, Sendable {
  var listenOnly: Bool
  var mask: Set<InputKind>

  static let production = TapConfig(listenOnly: true, mask: Set(InputKind.allCases))

  var options: CGEventTapOptions { listenOnly ? .listenOnly : .defaultTap }

  var eventMask: CGEventMask {
    mask.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.cgType.rawValue)) }
  }
}
