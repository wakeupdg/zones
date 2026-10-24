import CoreGraphics
import Foundation
import ZonesCore

/// Pure: decides the frame a Restore writes, or why it writes nothing (ADR-0009, ADR-0014).
public enum RestorePlanner {
  public static func plan(
    _ e: OriginalFrameEntry, window: WindowRef, facts: WindowFacts?, topology: TopologySnapshot
  ) -> Result<CGRect, NoOpReason> {
    // ADR-0014: nothing happens in a full-screen Space.
    if facts?.isFullScreen == true { return .failure(.fullScreen) }
    return .success(e.frame)
  }
}
