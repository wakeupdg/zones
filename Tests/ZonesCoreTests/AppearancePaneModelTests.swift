import Testing
import ZonesCore

@Suite struct AppearancePaneModelTests {
  private func builtIn(_ template: Template, _ count: Int, insets: Insets) -> Layout {
    Layout(
      id: LayoutID(rawValue: "builtin:\(template)):\(count)"), name: template.rawValue, root: .leaf,
      surround: Surround(top: 0, left: 0, bottom: 0, right: 0), insets: insets,
      builtIn: BuiltInRef(template: template, count: count))
  }

  @Test func listsFollowers() {
    let defaults = Insets(margin: 8, gap: 8)
    let columns = builtIn(.columns, 3, insets: Insets(margin: 0, gap: 0))  // built-ins always follow
    var same = TestFixtures.desk  // margin 8, gap 8
    same.id = LayoutID(rawValue: "same")
    let other = TestFixtures.centered  // margin 12, gap 6
    let layouts = [other, same, columns]

    #expect(AppearancePaneModel.followers(of: defaults, in: layouts) == [same.id, columns.id])
    #expect(AppearancePaneModel.followers(of: Insets(margin: 12, gap: 6), in: layouts) == [other.id, columns.id])
    #expect(AppearancePaneModel.followers(of: Insets(margin: 1, gap: 1), in: layouts) == [columns.id])
    #expect(AppearancePaneModel.followers(of: defaults, in: []).isEmpty)
  }
}
