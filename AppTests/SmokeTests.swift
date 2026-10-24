import Testing

@testable import Zones

@MainActor
struct AppShellTests {
  @Test func quitIsTheLastMenuItem() {
    #expect(AppDelegate.menuTitles.last == "Quit Zones")
  }
}
