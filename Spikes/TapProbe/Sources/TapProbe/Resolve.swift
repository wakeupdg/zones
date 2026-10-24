import CoreGraphics
import Foundation

/// Throwaway analogue of WindowEnumerator.candidates(under:hint:) plus the pid+frame match (AC-056: never by title).
struct Resolution: Equatable {
  var id: UInt32?
  var pid: Int32?
  var byField: Bool
  var byPidFrame: Bool
  var movedCandidates: Int
}

enum Resolver {
  /// Layer-0 windows whose frame contains the mouse-down point, z-ordered (front first).
  static func candidates(in list: [WindowInfo], under point: CGPoint) -> [WindowInfo] {
    list.filter { $0.layer == 0 && $0.frame.contains(point) }
  }

  /// `before`: candidates at mouse-down. `after`: full list re-read later. Matching uses pid + size, never ids or names:
  /// a candidate "moved" when exactly one after-entry of the same pid and size has a different origin and
  /// no after-entry of that pid and size kept the old origin.
  static func resolve(before: [WindowInfo], after: [WindowInfo], fieldID: UInt32?) -> Resolution {
    var moved = [(WindowInfo, WindowInfo)]()
    for old in before {
      let sameShape = after.filter { $0.layer == 0 && $0.pid == old.pid && $0.frame.size == old.frame.size }
      if sameShape.contains(where: { $0.frame.origin == old.frame.origin }) { continue }  // unchanged (or ambiguous twin)
      if sameShape.count == 1, let new = sameShape.first { moved.append((old, new)) }
    }
    guard moved.count == 1, let (old, new) = moved.first else {
      return Resolution(id: nil, pid: nil, byField: false, byPidFrame: false, movedCandidates: moved.count)
    }
    // The pid+frame answer is the same window the field names when the id is stable across both reads.
    return Resolution(
      id: new.id, pid: old.pid, byField: fieldID == new.id, byPidFrame: true, movedCandidates: 1)
  }

  static func line(_ r: Resolution) -> String {
    guard let id = r.id, let pid = r.pid else {
      return "RESOLVED pid=nil id=nil byField=\(r.byField) byPidFrame=false movedCandidates=\(r.movedCandidates)"
    }
    return "RESOLVED pid=\(pid) id=\(id) byField=\(r.byField) byPidFrame=\(r.byPidFrame)"
  }

  /// Logic self-test on fabricated lists (no events, no real windows). Labelled SYNTHETIC-LOGIC by the caller.
  static func selfTest() -> Bool {
    func w(_ id: UInt32, _ pid: Int32, _ x: Double, _ y: Double, layer: Int32 = 0) -> WindowInfo {
      WindowInfo(id: id, pid: pid, layer: layer, frame: CGRect(x: x, y: y, width: 400, height: 300), hasName: false, nameLength: 0, hasOwnerName: false, ownerName: nil)
    }
    let point = CGPoint(x: 150, y: 150)
    let beforeAll = [w(1, 10, 100, 100), w(2, 20, 100, 100), w(3, 30, 900, 900), w(4, 40, 0, 0, layer: 25)]
    let cands = candidates(in: beforeAll, under: point)
    let afterMoved = [w(1, 10, 160, 140), w(2, 20, 100, 100), w(3, 30, 900, 900), w(4, 40, 0, 0, layer: 25)]
    let r1 = resolve(before: cands, after: afterMoved, fieldID: 1)
    let r2 = resolve(before: cands, after: beforeAll, fieldID: 1)
    return cands.map(\.id) == [1, 2] && r1 == Resolution(id: 1, pid: 10, byField: true, byPidFrame: true, movedCandidates: 1)
      && !r2.byPidFrame && r2.movedCandidates == 0
  }
}
