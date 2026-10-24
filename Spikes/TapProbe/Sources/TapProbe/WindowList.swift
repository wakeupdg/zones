import CoreGraphics
import Foundation

/// Throwaway analogue of WindowRef (CONTRACTS.md): phase-1 CoreGraphics facts. Names are only probed for presence.
struct WindowInfo: Hashable, Sendable {
  var id: UInt32
  var pid: Int32
  var layer: Int32
  var frame: CGRect
  var hasName: Bool
  var nameLength: Int
  var hasOwnerName: Bool
  var ownerName: String?
}

struct ListReport: Sendable {
  var windows: [WindowInfo]  // front to back, as returned
  var total: Int
  var missingBounds = 0, missingLayer = 0, missingPid = 0, missingNumber = 0
  var namedCount: Int { windows.filter(\.hasName).count }
  var nonEmptyNamedCount: Int { windows.filter { $0.nameLength > 0 }.count }
  var ownerNamedCount: Int { windows.filter(\.hasOwnerName).count }
  var layer0: [WindowInfo] { windows.filter { $0.layer == 0 } }
}

enum WindowList {
  /// Mirrors the production call: on-screen only, desktop elements excluded.
  static func read() -> ListReport {
    let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    var report = ListReport(windows: [], total: raw.count)
    for entry in raw {
      guard let number = entry[kCGWindowNumber as String] as? UInt32 else { report.missingNumber += 1; continue }
      let pid = entry[kCGWindowOwnerPID as String] as? Int32
      let layer = entry[kCGWindowLayer as String] as? Int32
      let bounds = (entry[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
      if pid == nil { report.missingPid += 1 }
      if layer == nil { report.missingLayer += 1 }
      if bounds == nil { report.missingBounds += 1 }
      let name = entry[kCGWindowName as String] as? String
      let owner = entry[kCGWindowOwnerName as String] as? String
      report.windows.append(
        WindowInfo(
          id: number, pid: pid ?? -1, layer: layer ?? -1, frame: bounds ?? .zero,
          hasName: name != nil, nameLength: name?.count ?? 0, hasOwnerName: owner != nil, ownerName: owner))
    }
    return report
  }

  static func describe(_ r: ListReport) -> String {
    "WINDOWLIST total=\(r.total) layer0=\(r.layer0.count) missing(bounds=\(r.missingBounds) layer=\(r.missingLayer) pid=\(r.missingPid) number=\(r.missingNumber)) kCGWindowName-non-nil=\(r.namedCount) kCGWindowName-non-empty=\(r.nonEmptyNamedCount) kCGWindowOwnerName-non-nil=\(r.ownerNamedCount)"
  }

  static func describe(_ w: WindowInfo) -> String {
    let f = w.frame
    return String(
      format: "WINDOW id=%u pid=%d layer=%d bounds=(%.0f,%.0f,%.0f,%.0f) name=%@ ownerName=%@",
      w.id, w.pid, w.layer, f.origin.x, f.origin.y, f.size.width, f.size.height,
      w.hasName ? "present(len=\(w.nameLength))" : "nil", w.hasOwnerName ? "present(\(w.ownerName ?? ""))" : "nil")
  }
}
