import ApplicationServices
import CoreGraphics
import Foundation
import ZonesCore
import ZonesLayout
import ZonesTestSupport

@testable import ZonesWindowing

/// Real grid-rounded Zone rectangles from the built-in Templates, never hand-built frames.
enum ShortcutFixtures {
  static let displayA = DisplayKey.uuid("AAAAAAAA-1111-4111-8111-111111111111")
  static let displayB = DisplayKey.uuid("BBBBBBBB-2222-4222-8222-222222222222")
  static let visibleA = CGRect(x: 0, y: 25, width: 1920, height: 1055)
  static let visibleB = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
  static let frameA = CGRect(x: 0, y: 0, width: 1920, height: 1080)
  static let frameB = CGRect(x: 1920, y: 0, width: 2560, height: 1440)

  static func resolved(
    _ template: Template, count: Int, key: DisplayKey = displayA, visible: CGRect = visibleA, scale: Double = 2
  ) -> ResolvedLayout {
    let layout = Templates.generate(template, count: count, insets: Insets(margin: 0, gap: 0))
    return LayoutMath.resolve(layout, key: key, visibleFrame: visible, scale: scale)
  }

  static let key = WindowKey(pid: 4242, elementHash: 7)

  static let topology = TopologySnapshot(
    displays: [
      DisplaySnapshot(
        key: displayA, frame: frameA, visibleFrame: visibleA, scale: 2, isMain: true, mirrorOf: nil, name: "A",
        resolution: CGSize(width: 3840, height: 2160)),
      DisplaySnapshot(
        key: displayB, frame: frameB, visibleFrame: visibleB, scale: 2, isMain: false, mirrorOf: nil, name: "B",
        resolution: CGSize(width: 5120, height: 2880)),
    ], separateSpaces: true, primaryFrame: frameA)

  static func assignment(_ id: LayoutID) -> Assignment {
    Assignment(layout: id, displayName: "D", lastVisibleFrame: visibleA, lastScale: 2, lastSeen: nil)
  }

  /// Per-Display layouts the way the caller builds them: Assignment -> LayoutID -> Layout -> LayoutMath.resolve.
  static func layouts(a: LayoutID, b: LayoutID) -> [DisplayKey: ResolvedLayout] {
    let all = Templates.all(insets: Insets(margin: 0, gap: 0))
    var assignments: [String: Assignment] = [:]
    assignments["AAAAAAAA-1111-4111-8111-111111111111"] = assignment(a)
    assignments["BBBBBBBB-2222-4222-8222-222222222222"] = assignment(b)
    var out: [DisplayKey: ResolvedLayout] = [:]
    for d in topology.displays {
      let id = AssignmentLookup.layoutID(for: d.key, in: assignments, session: [:])
      let layout = all.first { $0.id == id }!
      out[d.key] = LayoutMath.resolve(layout, display: d)
    }
    return out
  }

  static func facts(
    fullScreen: Bool = false, positionSettable: Bool = true
  ) -> WindowFacts {
    WindowFacts(subrole: .standard, isFullScreen: fullScreen, positionSettable: positionSettable, sizeSettable: true)
  }

  static func handle(pid: pid_t = getpid()) -> WindowHandle {
    WindowHandle(element: AXUIElementCreateApplication(pid), pid: pid)
  }

  static func focused(
    frame: CGRect, facts: WindowFacts = facts(), handle: WindowHandle = handle()
  ) -> FocusedWindow {
    let ref = WindowRef(id: WindowID(rawValue: 1), pid: handle.pid, bundleID: "com.example.app", frame: frame, layer: 0)
    return FocusedWindow(record: WindowRecord(ref: ref, handle: handle, facts: facts), facts: facts, frame: frame)
  }
}
