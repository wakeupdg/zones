import AppKit
import CoreGraphics
import Foundation
import ZonesCore

/// Production `WindowEnumerator` over the CoreGraphics window list. Stateless.
///
/// Reads only window number, owner pid, bounds and layer. It never reads a window or owner name
/// (LI-003, ADR-0020): doing so is what would require Screen Recording permission. CG bounds are
/// top-left global, so each is converted to AppKit global with `CoordinateSpace.appKitRect`.
public struct CGWindowEnumerator: Sendable {
  private let primaryFrame: @Sendable () -> CGRect

  /// `primaryFrame` supplies the primary display frame (AppKit global) at call time.
  public init(primaryFrame: @escaping @Sendable () -> CGRect) {
    self.primaryFrame = primaryFrame
  }

  // MARK: Pure helpers (no window server)

  /// Parses CG window info dictionaries into layer-0 refs, preserving order. Entries missing a
  /// number, pid, bounds or layer are dropped. `bundleID` is asked once per pid per call.
  static func refs(
    from infos: [[String: Any]], primaryFrame: CGRect, bundleID: (pid_t) -> String?
  ) -> [ZonesCore.WindowRef] {
    var bundleIDs: [pid_t: String?] = [:]
    var refs: [ZonesCore.WindowRef] = []
    for info in infos {
      guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
        let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
        let layer = (info[kCGWindowLayer as String] as? NSNumber)?.int32Value,
        layer == 0,
        let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
        let cgBounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
      else { continue }
      let bundle: String?
      if let cached = bundleIDs[pid] {
        bundle = cached
      } else {
        bundle = bundleID(pid)
        bundleIDs[pid] = .some(bundle)
      }
      refs.append(
        ZonesCore.WindowRef(
          id: WindowID(rawValue: number), pid: pid, bundleID: bundle,
          frame: CoordinateSpace.appKitRect(cgBounds, primaryFrame: primaryFrame), layer: layer))
    }
    return refs
  }
}
