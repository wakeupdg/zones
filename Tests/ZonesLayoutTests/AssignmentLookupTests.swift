import CoreGraphics
import Foundation
import Testing
import ZonesCore

@testable import ZonesLayout

private func assignment(_ layout: String) -> Assignment {
  Assignment(
    layout: LayoutID(rawValue: layout), displayName: "D", lastVisibleFrame: CGRect(x: 0, y: 0, width: 100, height: 50),
    lastScale: 2, lastSeen: nil)
}

struct AssignmentLookupTests {
  @Test func unknownDisplayGetsPriorityGrid() {
    let expected = Templates.builtInID(.priorityGrid, count: 3)
    #expect(expected.rawValue == "builtin:priorityGrid:3")
    #expect(AssignmentLookup.layoutID(for: .uuid("X"), in: [:], session: [:]) == expected)
    #expect(AssignmentLookup.layoutID(for: .unstable("tmp"), in: [:], session: [:]) == expected)
  }
}
