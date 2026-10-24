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

  @Test func grantItemOnlyWhenNotGranted() {
    for p in allPermissionSamples {
      let items = Self.build(permission: p).filter { $0 != .separator }
      let shows: Bool
      switch p {
      case .granted, .suspect: shows = false
      default: shows = true
      }
      #expect(items.contains(.grantAccessibility) == shows, "\(p)")
      if shows, let i = items.firstIndex(of: MenuItem.grantAccessibility) {
        #expect(items[i - 1] == .settings && items[i + 1] == .about)
      }
    }
  }

  @Test func excludeItemFollowsFrontmost() {
    #expect(!Self.build(frontmost: nil).contains { if case .excludeApp = $0 { true } else { false } })
    let free = Self.build(exclusions: [])
    #expect(free.contains(.excludeApp(name: "Safari", bundleID: "com.apple.Safari", checked: false)))
  }

  @Test func nilDisplayAndMissingLayout() {
    let none = Self.build(display: nil)
    #expect(none.first == .header("No display"))
    #expect(!none.contains { if case .layout(_, _, true) = $0 { true } else { false } })
    #expect(none.contains { if case .layout = $0 { true } else { false } })
    let ghost = LayoutID(rawValue: "ghost")
    let missing = Self.build(assignment: ghost)
    #expect(missing.first == .header("Studio — ghost"))
    #expect(!missing.contains { if case .layout(_, _, true) = $0 { true } else { false } })
    let both = Self.build(display: nil, assignment: ghost)
    #expect(both.first == .header("No display"))
  }

  @Test func separatorsNeverAdjacentOrAtEnds() {
    for p in allPermissionSamples {
      for frontmost in [Self.safari, nil] {
        let items = Self.build(frontmost: frontmost, permission: p)
        #expect(items.first != .separator && items.last != .separator)
        #expect(!zip(items, items.dropFirst()).contains { $0 == .separator && $1 == .separator })
      }
    }
  }

  // AC-017
  @MainActor @Test func buildsWithoutActorCalls() {
    let clock = FakeClock()  // never advanced: any window-system call would stay in flight
    let ws = FakeWindowSystem(clock: clock)
    ws.latency = 60
    let items = Self.build()
    #expect(!items.isEmpty)
    #expect(ws.calls.isEmpty)
    #expect(ws.inFlight == 0)
  }
}
