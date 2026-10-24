import AppKit
import ZonesCore
import ZonesLayout

/// Pure geometry for the editor canvas. The editor never recomputes layout math: every rectangle here is a
/// `ResolvedLayout` frame from `LayoutMath.resolve` (via `EditorState.preview`), only translated into view space.
enum EditorCanvasGeometry {
  struct ZoneRect: Hashable {
    var number: Int
    var path: NodePath
    var rect: CGRect
  }

  /// Each Zone's frame in view coordinates. `contentOrigin` is the screen position (AppKit coordinates, y up) of
  /// the view's bottom-left corner; subtracting it is the only change, so 1 view point is 1 screen point and the
  /// Zones stay on the same screen pixels when the window moves or resizes.
  static func zoneRects(preview: ResolvedLayout, contentOrigin: CGPoint) -> [ZoneRect] {
    preview.zones.map {
      ZoneRect(
        number: $0.number, path: $0.path, rect: $0.frame.offsetBy(dx: -contentOrigin.x, dy: -contentOrigin.y))
    }
  }
}
