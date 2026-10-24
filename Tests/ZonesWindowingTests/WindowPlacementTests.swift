import AppKit
import Testing
import ZonesCore
import ZonesWindowing

@Suite struct WindowPlacementTests {
  static func display(_ id: String, frame: CGRect, visible: CGRect, main: Bool) -> DisplaySnapshot {
    DisplaySnapshot(
      key: .uuid(id), frame: frame, visibleFrame: visible, scale: 2, isMain: main, mirrorOf: nil,
      name: id, resolution: frame.size)
  }

  static let a = display(
    "A", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visible: CGRect(x: 0, y: 0, width: 1512, height: 944), main: true)
  static let b = display(
    "B", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
    visible: CGRect(x: 1512, y: 25, width: 2560, height: 1415), main: false)

  static func topology(_ displays: [DisplaySnapshot]) -> TopologySnapshot {
    TopologySnapshot(displays: displays, separateSpaces: true, primaryFrame: a.frame)
  }

  // AC-022
  @Test func opensOnCursorDisplay() throws {
    let topo = Self.topology([Self.a, Self.b])
    let size = CGSize(width: 720, height: 520)

    for (point, expected) in [
      (CGPoint(x: 2000, y: 700), Self.b), (CGPoint(x: 400, y: 300), Self.a),
    ] {
      let found = try #require(WindowPlacement.cursorDisplay(cursor: point, in: topo))
      #expect(found == expected)
      let frame = WindowPlacement.settingsFrame(cursor: found, size: size)
      #expect(frame.midX == expected.visibleFrame.midX)
      #expect(frame.midY == expected.visibleFrame.midY)
      #expect(frame.size == size)
      #expect(expected.visibleFrame.contains(frame))
      #expect(WindowPlacement.editorFrame(cursor: found) == expected.visibleFrame)
    }

    let huge = WindowPlacement.settingsFrame(cursor: Self.b, size: CGSize(width: 9000, height: 9000))
    #expect(huge == Self.b.visibleFrame)

    let off = try #require(WindowPlacement.cursorDisplay(cursor: CGPoint(x: -500, y: -500), in: topo))
    #expect(off == Self.a)
    #expect(WindowPlacement.cursorDisplay(cursor: .zero, in: Self.topology([])) == nil)

    #expect(NSWindow.StyleMask(rawValue: WindowPlacement.settingsStyleMaskRaw).contains(.resizable))
    #expect(NSWindow.StyleMask(rawValue: WindowPlacement.editorStyleMaskRaw).contains(.resizable))
  }
}
