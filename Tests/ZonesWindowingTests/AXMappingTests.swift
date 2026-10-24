import CoreGraphics
import Testing
import ZonesCore

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
}
