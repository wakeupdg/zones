import CoreGraphics
import Foundation
import ZonesCore
import ZonesTestSupport

/// A Layout wrapper for property tests: the failure message needs a Layout, the math needs the pieces.
func makeLayout(
  root: SplitNode, surround: Surround = Surround(top: 0, left: 0, bottom: 0, right: 0),
  insets: Insets = Insets(margin: 0, gap: 0)
) -> Layout {
  Layout(id: LayoutID(rawValue: "test"), name: "test", root: root, surround: surround, insets: insets)
}

func leafCount(_ node: SplitNode) -> Int {
  switch node {
  case .leaf: 1
  case .split(_, _, let first, let second): leafCount(first) + leafCount(second)
  }
}

/// Every split ratio in the tree.
func ratios(_ node: SplitNode) -> [Double] {
  switch node {
  case .leaf: []
  case .split(_, let ratio, let first, let second): [ratio] + ratios(first) + ratios(second)
  }
}
