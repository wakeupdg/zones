import Foundation
import ZonesCore

/// One editor action (US-105 to US-116). `EditorError` lives in ZonesCore.
public enum EditorCommand: Hashable, Sendable {
  case select(NodePath?)
  case split(SplitAxis)
  case merge
  case setRatio(NodePath, Double, snap: Bool)
  case nudge(NodePath, points: Double)
  case setMargin(Double)
  case setGap(Double)
  case template(Template, count: Int)
  case rename(String)
}

/// The Layout being edited, the selected node (a leaf is a Zone, a split is its divider) and whether it differs
/// from what was last saved.
public struct EditorDraft: Hashable, Sendable {
  public var layout: Layout
  public var selection: NodePath?
  public var dirty: Bool

  public init(layout: Layout, selection: NodePath? = nil, dirty: Bool = false) {
    self.layout = layout
    self.selection = selection
    self.dirty = dirty
  }
}
