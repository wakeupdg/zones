import CoreGraphics
import Foundation
import Testing
import ZonesCore

@testable import ZonesWindowing

@Suite struct CGWindowEnumeratorTests {
  static let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)

  static func info(
    id: UInt32, pid: Int32, bounds: CGRect, layer: Int32, decoys: Bool = true
  ) -> [String: Any] {
    var dict: [String: Any] = [
      kCGWindowNumber as String: NSNumber(value: id),
      kCGWindowOwnerPID as String: NSNumber(value: pid),
      kCGWindowBounds as String: CGRectCreateDictionaryRepresentation(bounds),
      kCGWindowLayer as String: NSNumber(value: layer),
    ]
    if decoys {
      dict[kCGWindowName as String] = "SECRET-TITLE-\(id)"
      dict[kCGWindowOwnerName as String] = "SECRET-OWNER-\(id)"
    }
    return dict
  }

  @Test func parseKeepsLayerZeroAndNoNames() {
    let infos = [
      Self.info(id: 5, pid: 10, bounds: CGRect(x: 100, y: 50, width: 300, height: 200), layer: 0),
      Self.info(id: 6, pid: 11, bounds: CGRect(x: 0, y: 0, width: 1000, height: 24), layer: 25),
      Self.info(id: 7, pid: 12, bounds: CGRect(x: 0, y: 0, width: 400, height: 300), layer: 0),
      Self.info(id: 8, pid: 10, bounds: CGRect(x: 0, y: 0, width: 10, height: 10), layer: -1),
    ]
    var asked: [pid_t] = []
    let refs = CGWindowEnumerator.refs(from: infos, primaryFrame: Self.primary) { pid in
      asked.append(pid)
      return "bundle.\(pid)"
    }
    #expect(refs.map(\.id.rawValue) == [5, 7])
    #expect(refs.map(\.pid) == [10, 12])
    #expect(refs.map(\.bundleID) == ["bundle.10", "bundle.12"])
    #expect(refs.allSatisfy { $0.layer == 0 })
    // top-left CG bounds become bottom-left AppKit frames against the primary frame
    #expect(refs[0].frame == CGRect(x: 100, y: 800 - 50 - 200, width: 300, height: 200))
    #expect(refs[1].frame == CGRect(x: 0, y: 500, width: 400, height: 300))
    let text = String(describing: refs)
    #expect(!text.contains("SECRET"))
    // layer filtering happens before any bundle lookup
    #expect(!asked.contains(11))
  }

  @Test func parseDropsMalformedEntries() {
    let good = Self.info(id: 1, pid: 2, bounds: CGRect(x: 0, y: 0, width: 5, height: 5), layer: 0)
    var noBounds = good
    noBounds[kCGWindowBounds as String] = nil
    var noNumber = good
    noNumber[kCGWindowNumber as String] = nil
    let refs = CGWindowEnumerator.refs(
      from: [noBounds, noNumber, good], primaryFrame: Self.primary) { _ in nil }
    #expect(refs.count == 1)
    #expect(refs[0].bundleID == nil)
  }
}
