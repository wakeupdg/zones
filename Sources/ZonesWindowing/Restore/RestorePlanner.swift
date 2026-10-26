import CoreGraphics
import Foundation
import ZonesCore

/// Pure: decides the frame a Restore writes, or why it writes nothing (ADR-0009, ADR-0014).
/// The entry, the window and the topology are all in one coordinate space; the caller converts.
public enum RestorePlanner {
  public static func plan(
    _ e: OriginalFrameEntry, window: WindowRef, facts: WindowFacts?, topology: TopologySnapshot
  ) -> Result<CGRect, NoOpReason> {
    // ADR-0014: nothing happens in a full-screen Space.
    if facts?.isFullScreen == true { return .failure(.fullScreen) }
    // Any overlap with a Display (a straddle included) leaves the Original Frame as it was.
    if CoordinateSpace.display(for: e.frame, in: topology) != nil { return .success(e.frame) }
    // The Display it lived on is gone: bring it into the Display the window overlaps most now,
    // else the main Display, else the first one. With no Display at all there is nothing to clamp to.
    let target =
      CoordinateSpace.display(for: window.frame, in: topology)
      ?? topology.displays.first(where: \.isMain) ?? topology.displays.first
    guard let target else { return .success(e.frame) }
    return .success(fit(e.frame, into: target.visibleFrame))
  }

  /// Same size, shrunk only if larger than `area`, moved the least distance that puts it inside.
  static func fit(_ frame: CGRect, into area: CGRect) -> CGRect {
    let width = min(frame.width, area.width)
    let height = min(frame.height, area.height)
    let x = min(max(frame.minX, area.minX), area.maxX - width)
    let y = min(max(frame.minY, area.minY), area.maxY - height)
    return CGRect(x: x, y: y, width: width, height: height)
  }
}
