import CoreGraphics
import Testing
import ZonesCore
import ZonesLayout
import ZonesTestSupport
import ZonesWindowing

@Suite struct MenuModelTests {
  static let insets = Insets(margin: 8, gap: 8)
  static let desk = Layout(
    id: LayoutID(rawValue: "00000000-0000-0000-0000-0000000000D1"), name: "Desk", root: .leaf,
    surround: Surround(top: 0, left: 0, bottom: 0, right: 0), insets: insets)
  static let stream = Layout(
    id: LayoutID(rawValue: "00000000-0000-0000-0000-0000000000D2"), name: "Stream", root: .leaf,
    surround: Surround(top: 0, left: 0, bottom: 0, right: 0), insets: insets)

  static func store() -> LayoutStore {
    LayoutStore(document: ZonesDocument(layouts: [desk, stream]), defaults: insets)
  }

  static func display(_ name: String = "Studio") -> DisplaySnapshot {
    DisplaySnapshot(
      key: .uuid("B"), frame: CGRect(x: 0, y: 0, width: 100, height: 100),
      visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 90), scale: 2, isMain: false, mirrorOf: nil,
      name: name, resolution: CGSize(width: 200, height: 200))
  }

  static let columns3 = Templates.builtInID(.columns, count: 3)
  static let safari = (name: "Safari", bundleID: "com.apple.Safari")

  static func build(
    display: DisplaySnapshot? = display(), assignment: LayoutID = columns3,
    frontmost: (name: String, bundleID: String)? = safari, exclusions: Set<String> = ["com.apple.Safari"],
    permission: PermissionState = .notGranted
  ) -> [MenuItem] {
    MenuModel.build(
      cursorDisplay: display, assignment: assignment, store: store(), frontmost: frontmost, exclusions: exclusions,
      permission: permission)
  }

  // AC-016
  @Test func orderAndStateForDisplayUnderCursor() {
    let s = Self.store()
    let items = Self.build().filter { $0 != .separator }
    var expected: [MenuItem] = [.header("Studio — Columns 3")]
    for l in s.builtIns + s.custom {
      let title = l.builtIn.map { "\($0.template.rawValue) \($0.count)" } ?? l.name
      expected.append(.layout(l.id, title: title, checked: l.id == Self.columns3))
    }
    expected += [
      .excludeApp(name: "Safari", bundleID: "com.apple.Safari", checked: true),
      .editLayouts, .settings, .grantAccessibility, .about, .quit,
    ]
    #expect(items == expected)
    #expect(items.count == 1 + 12 + 2 + 1 + 5)
    #expect(items.contains(.layout(Self.columns3, title: "Columns 3", checked: true)))
    #expect(items.contains(.layout(Self.desk.id, title: "Desk", checked: false)))
  }
}
