import CoreGraphics
import ZonesCore

/// Where the Settings and editor windows open (AC-022): on the Display under the cursor.
public enum WindowPlacement {
  /// `NSWindow.StyleMask` raw bits: titled (1) | closable (2) | miniaturizable (4) | resizable (8).
  /// Raw bits rather than the AppKit type so Shell/ stays AppKit-free.
  public static let settingsStyleMaskRaw: UInt = 1 | 2 | 4 | 8
  /// titled (1) | closable (2) | resizable (8).
  public static let editorStyleMaskRaw: UInt = 1 | 2 | 8

  /// The Display whose `frame` contains the cursor, else the main Display (else the first, else nil).
  public static func cursorDisplay(cursor: CGPoint, in topology: TopologySnapshot) -> DisplaySnapshot? {
    topology.displays.first { $0.frame.contains(cursor) }
      ?? topology.displays.first { $0.isMain } ?? topology.displays.first
  }

  /// `size` clamped to the Display's visible frame, centered in it.
  public static func settingsFrame(cursor: DisplaySnapshot, size: CGSize) -> CGRect {
    let visible = cursor.visibleFrame
    let clamped = CGSize(width: min(size.width, visible.width), height: min(size.height, visible.height))
    return CGRect(
      x: visible.midX - clamped.width / 2, y: visible.midY - clamped.height / 2,
      width: clamped.width, height: clamped.height)
  }

  public static func editorFrame(cursor: DisplaySnapshot) -> CGRect { cursor.visibleFrame }
}
