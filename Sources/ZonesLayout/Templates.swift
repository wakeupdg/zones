import CoreGraphics
import Foundation
import ZonesCore

/// Built-in Templates (ADR-0005). Pure value functions: ids are derived from Template and count at load and
/// are never persisted.
public enum Templates {
  /// `builtin:<camelCase>:<count>`, with the camelCase taken from the Template case name.
  public static func builtInID(_ t: Template, count: Int) -> LayoutID {
    LayoutID(rawValue: "builtin:\(caseName(t)):\(count)")
  }

  /// The Layout for `t` with `count` Zones. `name` is `t.rawValue` (no count suffix); the id and `builtIn`
  /// distinguish counts. Surround is zero except for Focus.
  public static func generate(_ t: Template, count: Int, insets: Insets) -> Layout {
    let zero = Surround(top: 0, left: 0, bottom: 0, right: 0)
    let f = Constants.focusSurround
    let surround = t == .focus ? Surround(top: f, left: f, bottom: f, right: f) : zero
    return Layout(
      id: builtInID(t, count: count), name: t.rawValue, root: tree(t, count: count), surround: surround,
      insets: insets, builtIn: BuiltInRef(template: t, count: count))
  }

  /// Every built-in, in `Template.allCases` order with each Template's counts ascending: 12 Layouts.
  public static func all(insets: Insets) -> [Layout] {
    Template.allCases.flatMap { t in t.counts.map { generate(t, count: $0, insets: insets) } }
  }

  /// A custom copy: fresh id, name "<name> copy", no `builtIn`, `insets` (the current defaults) made explicit.
  /// Root and surround are copied.
  public static func duplicate(_ l: Layout, insets: Insets, newID: LayoutID) -> Layout {
    Layout(
      id: newID, name: "\(l.name) copy", root: l.root, surround: l.surround, insets: insets, builtIn: nil)
  }

  private static func caseName(_ t: Template) -> String {
    switch t {
    case .columns: "columns"
    case .rows: "rows"
    case .grid: "grid"
    case .priorityGrid: "priorityGrid"
    case .focus: "focus"
    }
  }

  private static func tree(_ t: Template, count: Int) -> SplitNode {
    switch t {
    case .columns: strip(.horizontal, count: count)
    case .rows: strip(.vertical, count: count)
    case .grid: grid(side: count == 9 ? 3 : 2)
    case .priorityGrid:
      .split(
        axis: .horizontal, ratio: 0.25, first: .leaf,
        second: .split(axis: .horizontal, ratio: 2.0 / 3, first: .leaf, second: .leaf))
    case .focus: .leaf
    }
  }

  /// Right-nested splits along `axis`; the k-th split (0-based) gives its first child `1/(n-k)`.
  private static func strip(_ axis: SplitAxis, count: Int) -> SplitNode {
    guard count > 1 else { return .leaf }
    return .split(axis: axis, ratio: 1.0 / Double(count), first: .leaf, second: strip(axis, count: count - 1))
  }

  /// `side` rows of `side` cells: vertical strip of horizontal strips.
  private static func grid(side: Int) -> SplitNode {
    guard side > 1 else { return .leaf }
    let row = strip(.horizontal, count: side)
    return .split(axis: .vertical, ratio: 1.0 / Double(side), first: row, second: gridRows(row, count: side - 1))
  }

  private static func gridRows(_ row: SplitNode, count: Int) -> SplitNode {
    guard count > 1 else { return row }
    return .split(axis: .vertical, ratio: 1.0 / Double(count), first: row, second: gridRows(row, count: count - 1))
  }
}
