import CoreGraphics
import Foundation
import ZonesCore

/// One command in, one new draft or an error out; the input draft is a value and is never touched.
public enum EditorEngine {
  public static func apply(
    _ c: EditorCommand, to d: EditorDraft, geometry: (visibleFrame: CGRect, scale: Double)
  ) -> Result<EditorDraft, EditorError> {
    switch c {
    case .select(let path): select(path, d)
    case .split(let axis): split(axis, d)
    case .merge: merge(d)
    case .setRatio(let path, let ratio, _): setRatio(path, ratio, d)
    default: .failure(.invalidRatio)
    }
  }

  // MARK: select

  private static func select(_ path: NodePath?, _ d: EditorDraft) -> Result<EditorDraft, EditorError> {
    if let path, node(at: path.steps[...], in: d.layout.root) == nil { return .failure(.nothingSelected) }
    var next = d
    next.selection = path
    return .success(next)
  }

  // MARK: split

  private static func split(_ axis: SplitAxis, _ d: EditorDraft) -> Result<EditorDraft, EditorError> {
    guard let path = d.selection, let target = node(at: path.steps[...], in: d.layout.root), target == .leaf else {
      return .failure(.nothingSelected)
    }
    let replacement = SplitNode.split(axis: axis, ratio: 0.5, first: .leaf, second: .leaf)
    var next = d
    next.layout.root = replacing(path.steps[...], in: d.layout.root, with: replacement)
    next.selection = NodePath(steps: path.steps + [false])
    return validated(next)
  }

  // MARK: merge

  /// Sibling-only (AC-129): the selected leaf and its sibling must both be leaves; the parent becomes a leaf.
  private static func merge(_ d: EditorDraft) -> Result<EditorDraft, EditorError> {
    guard let path = d.selection, let target = node(at: path.steps[...], in: d.layout.root), target == .leaf else {
      return .failure(.nothingSelected)
    }
    guard let last = path.steps.last else { return .failure(.rootMerge) }
    let parentSteps = Array(path.steps.dropLast())
    let siblingSteps = parentSteps + [!last]
    guard node(at: siblingSteps[...], in: d.layout.root) == .leaf else {
      return .failure(.notSiblings(hint: "split the parent the other way first"))
    }
    var next = d
    next.layout.root = replacing(parentSteps[...], in: d.layout.root, with: .leaf)
    next.selection = NodePath(steps: parentSteps)
    return validated(next)
  }

  // MARK: setRatio

  private static func setRatio(_ path: NodePath, _ ratio: Double, _ d: EditorDraft) -> Result<EditorDraft, EditorError> {
    guard ratio > 0, ratio < 1, case .split(let axis, _, let first, let second)? = node(at: path.steps[...], in: d.layout.root)
    else { return .failure(.invalidRatio) }
    var next = d
    next.layout.root = replacing(
      path.steps[...], in: d.layout.root, with: .split(axis: axis, ratio: ratio, first: first, second: second))
    return validated(next)
  }

  // MARK: warnings

  /// Numbers of Zones resolving under `Constants.usableSize` (120 x 80 pt) on the current Display.
  public static func warnings(_ r: ResolvedLayout) -> Set<Int> {
    Set(
      r.zones.filter { $0.frame.width < Constants.usableSize.width || $0.frame.height < Constants.usableSize.height }
        .map(\.number))
  }

  // MARK: shared helpers

  /// Marks the draft dirty and maps a validator fault to an `EditorError`. Faults that are not the command's
  /// doing (name, surround) are ignored: a draft may legitimately carry an empty name.
  private static func validated(_ d: EditorDraft) -> Result<EditorDraft, EditorError> {
    switch LayoutValidator.validate(d.layout) {
    case .leafTooSmall: return .failure(.tooSmall)
    case .ratioOutOfRange: return .failure(.invalidRatio)
    case .emptyName, .surroundOutOfRange, .overlap, nil:
      var out = d
      out.dirty = true
      return .success(out)
    }
  }

  static func node(at steps: ArraySlice<Bool>, in root: SplitNode) -> SplitNode? {
    guard let step = steps.first else { return root }
    guard case .split(_, _, let first, let second) = root else { return nil }
    return node(at: steps.dropFirst(), in: step ? second : first)
  }

  static func replacing(_ steps: ArraySlice<Bool>, in root: SplitNode, with new: SplitNode) -> SplitNode {
    guard let step = steps.first else { return new }
    guard case .split(let axis, let ratio, let first, let second) = root else { return root }
    let rest = steps.dropFirst()
    return step
      ? .split(axis: axis, ratio: ratio, first: first, second: replacing(rest, in: second, with: new))
      : .split(axis: axis, ratio: ratio, first: replacing(rest, in: first, with: new), second: second)
  }
}
