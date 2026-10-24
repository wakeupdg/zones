import CoreGraphics

/// The one place AppKit and Accessibility coordinates convert (AC-164).
///
/// AppKit global space has its origin at the bottom-left of the primary display with y up. Accessibility space has
/// its origin at the top-left of the primary display with y down. A rect above the primary display therefore has a
/// negative AX y.
public enum CoordinateSpace {
  /// AppKit global to AX. Only y changes: `y = primaryFrame.maxY - (appKit.y + appKit.height)`.
  public static func axRect(_ appKit: CGRect, primaryFrame: CGRect) -> CGRect {
    CGRect(
      x: appKit.origin.x, y: primaryFrame.maxY - (appKit.origin.y + appKit.size.height),
      width: appKit.size.width, height: appKit.size.height)
  }

  /// AX to AppKit global; the exact inverse of `axRect` (the flip is its own inverse).
  public static func appKitRect(_ ax: CGRect, primaryFrame: CGRect) -> CGRect {
    CGRect(
      x: ax.origin.x, y: primaryFrame.maxY - (ax.origin.y + ax.size.height),
      width: ax.size.width, height: ax.size.height)
  }

  /// The Display whose frame has the largest intersection area with `rect`. Ties go to the earlier Display in
  /// `snapshot.displays`; nil when the rect overlaps no Display with positive area.
  public static func display(for rect: CGRect, in snapshot: TopologySnapshot) -> DisplaySnapshot? {
    var best: (display: DisplaySnapshot, area: Double)?
    for display in snapshot.displays {
      let overlap = rect.intersection(display.frame)
      guard !overlap.isNull else { continue }
      let area = Double(overlap.width * overlap.height)
      if area > (best?.area ?? 0) { best = (display, area) }
    }
    return best?.display
  }

  /// Same size, origin relative to the panel's origin. Still y-up; flipping for SwiftUI is the view's job.
  public static func panelLocal(_ appKit: CGRect, panelFrame: CGRect) -> CGRect {
    CGRect(
      x: appKit.origin.x - panelFrame.origin.x, y: appKit.origin.y - panelFrame.origin.y,
      width: appKit.size.width, height: appKit.size.height)
  }
}
