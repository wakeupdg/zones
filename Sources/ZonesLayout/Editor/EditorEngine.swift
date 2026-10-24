import CoreGraphics
import Foundation
import ZonesCore

/// One command in, one new draft or an error out; the input draft is a value and is never touched.
public enum EditorEngine {
  public static func apply(
    _ c: EditorCommand, to d: EditorDraft, geometry: (visibleFrame: CGRect, scale: Double)
  ) -> Result<EditorDraft, EditorError> {
    switch c {
    case .split(let axis): split(axis, d)
    default: .failure(.invalidRatio)
    }
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
