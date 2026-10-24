import CoreGraphics
import Foundation
import Testing
import ZonesCore
import ZonesTestSupport

@testable import ZonesWindowing

@Suite struct InputSourceTests {
  static let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)

  // AC-065
  @Test func productionTapIsListenOnly() {
    #expect(TapConfig.production.listenOnly == true)
    #expect(TapConfig.production.mask == [.leftDown, .leftDragged, .leftUp, .flagsChanged])

    let source = EventTapInputSource(tapMaker: TapMaker { _, _ in nil }, primaryFrame: { Self.primary })
    #expect(source.config == .production)

    let expected: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
    let mask = EventTapInputSource.cgEventMask(for: .production)
    #expect(mask == expected.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) })
    let forbidden: [CGEventType] = [
      .rightMouseDown, .rightMouseDragged, .rightMouseUp, .otherMouseDown, .otherMouseDragged,
      .otherMouseUp, .keyDown, .keyUp, .mouseMoved, .scrollWheel,
    ]
    for type in forbidden {
      #expect(mask & (1 << CGEventMask(type.rawValue)) == 0, "\(type)")
    }
  }
}
