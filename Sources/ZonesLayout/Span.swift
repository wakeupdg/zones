import CoreGraphics
import ZonesCore

public enum Span {
  /// The bounding union of the frames of the named Zones. Numbers not in the layout are ignored and an empty
  /// result is `.zero`. No Margin or Gap arithmetic: the union of frames already spans the Gaps between them.
  public static func rect(_ zones: Set<Int>, in layout: ResolvedLayout) -> CGRect {
    let union = layout.zones.filter { zones.contains($0.number) }
      .reduce(CGRect.null) { $0.union($1.frame) }
    return union.isNull ? .zero : union
  }
}
