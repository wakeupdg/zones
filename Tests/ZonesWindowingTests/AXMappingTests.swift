import CoreGraphics
import Testing
import ZonesCore
import ZonesTestSupport

@testable import ZonesWindowing

@Suite struct AXMappingTests {
  @Test(arguments: [
    (Int32(-25204), AXStatus.timedOut),
    (Int32(-25202), AXStatus.elementGone),
    (Int32(-25211), AXStatus.apiDisabled),
    (Int32(-25205), AXStatus.refused(-25205)),
    (Int32(-25212), AXStatus.refused(-25212)),
  ])
  func statusFromAXErrorCode(code: Int32, expected: AXStatus) {
    #expect(AXStatus(axErrorCode: code) == expected)
    let failure: AXRead<CGRect> = .failure(axErrorCode: code)
    switch (failure, expected) {
    case (.timedOut, .timedOut), (.elementGone, .elementGone), (.apiDisabled, .apiDisabled): break
    case (.refused(let a), .refused(let b)): #expect(a == b)
    default: Issue.record("AXRead failure \(failure) does not match \(expected)")
    }
  }

  @Test func okCodeMapsToOk() {
    #expect(AXStatus(axErrorCode: 0) == .ok)
  }

  @Test(arguments: [
    ("AXStandardWindow", "AXWindow", Subrole.standard),
    ("AXDialog", "AXWindow", Subrole.dialog),
    ("AXSystemDialog", "AXWindow", Subrole.systemDialog),
    ("AXSystemFloatingWindow", "AXWindow", Subrole.systemFloatingWindow),
    ("AXFloatingWindow", "AXWindow", Subrole.floating),
    (nil, "AXSheet", Subrole.sheet),
    (nil, "AXPopover", Subrole.popover),
    ("AXSomethingNew", "AXWindow", Subrole.unknown),
    (nil, "AXWindow", Subrole.unknown),
    (nil, nil, Subrole.unknown),
  ] as [(String?, String?, Subrole)])
  func subroleMapping(axSubrole: String?, axRole: String?, expected: Subrole) {
    #expect(Subrole(axSubrole: axSubrole, axRole: axRole) == expected)
  }

  @Test func coordinateRoundTrip() {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    // A window flush with the top of the primary: AppKit y = 900 - height, AX y = 0.
    let flush = CGRect(x: 100, y: 900 - 300, width: 400, height: 300)
    #expect(AXGeometry.ax(flush, primaryFrame: primary).minY == 0)
    // A window on a secondary display above the primary has a negative AX y.
    let above = CGRect(x: 0, y: 900, width: 800, height: 600)
    #expect(AXGeometry.ax(above, primaryFrame: primary).minY < 0)
    #expect(AXGeometry.appKit(AXGeometry.ax(above, primaryFrame: primary), primaryFrame: primary) == above)
    // A primary that is not at the AX origin (display arrangement offsets).
    let offsetPrimary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let bounds = CGRect(x: -2000, y: -1500, width: 6000, height: 4000)
    for primaryFrame in [primary, offsetPrimary] {
      for seed in 0..<200 {
        var g = Generator(seed: UInt64(seed))
        let r = g.rect(in: bounds)
        let back = AXGeometry.appKit(AXGeometry.ax(r, primaryFrame: primaryFrame), primaryFrame: primaryFrame)
        #expect(abs(back.minX - r.minX) <= Constants.frameTolerance, "seed=\(seed)")
        #expect(abs(back.minY - r.minY) <= Constants.frameTolerance, "seed=\(seed)")
        #expect(abs(back.width - r.width) <= Constants.frameTolerance, "seed=\(seed)")
        #expect(abs(back.height - r.height) <= Constants.frameTolerance, "seed=\(seed)")
      }
    }
  }
}
