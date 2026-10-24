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

  @Test func sessionOverridesPersisted() {
    let uuid = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    let persisted = [uuid: assignment("persisted")]
    let session: [DisplayKey: LayoutID] = [
      .uuid(uuid): LayoutID(rawValue: "session"), .unstable("tmp"): LayoutID(rawValue: "tmpLayout"),
    ]
    #expect(AssignmentLookup.layoutID(for: .uuid(uuid), in: persisted, session: session).rawValue == "session")
    #expect(AssignmentLookup.layoutID(for: .uuid(uuid), in: persisted, session: [:]).rawValue == "persisted")
    #expect(AssignmentLookup.layoutID(for: .unstable("tmp"), in: persisted, session: session).rawValue == "tmpLayout")
    #expect(
      AssignmentLookup.layoutID(for: .unstable(uuid), in: persisted, session: [:])
        == Templates.builtInID(.priorityGrid, count: 3))
  }
}
