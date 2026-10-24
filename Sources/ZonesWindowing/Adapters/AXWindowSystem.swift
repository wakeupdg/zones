import ApplicationServices
import CoreGraphics
import Foundation
import ZonesCore

// MARK: Error mapping (pure; tested without a live AX connection)

/// Raw `AXError` codes, kept as literals so tests need no `ApplicationServices` import.
enum AXCode {
  static let cannotComplete: Int32 = -25204
  static let invalidUIElement: Int32 = -25202
  static let apiDisabled: Int32 = -25211
}

extension AXStatus {
  /// 0 is ok; CannotComplete is a timeout; InvalidUIElement is a gone element; APIDisabled is revocation.
  init(axErrorCode code: Int32) {
    switch code {
    case 0: self = .ok
    case AXCode.cannotComplete: self = .timedOut
    case AXCode.invalidUIElement: self = .elementGone
    case AXCode.apiDisabled: self = .apiDisabled
    default: self = .refused(code)
    }
  }
}

extension AXRead {
  /// The failure case for a non-zero `AXError` code. Code 0 is not a failure; it maps to `refused(0)`.
  static func failure(axErrorCode code: Int32) -> AXRead<T> {
    switch code {
    case AXCode.cannotComplete: .timedOut
    case AXCode.invalidUIElement: .elementGone
    case AXCode.apiDisabled: .apiDisabled
    default: .refused(code)
    }
  }
}
