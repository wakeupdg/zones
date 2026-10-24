import Testing

@testable import ZonesWindowing

@Suite struct AXPermissionProbeTests {
  @Test func probeValues() {
    #expect(AXPermissionProbe(launchedAtLogin: true).launchedAtLogin)
    #expect(!AXPermissionProbe(launchedAtLogin: false).launchedAtLogin)
    #expect(
      AXPermissionProbe.settingsURL.absoluteString
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    // Callable, never prompts; the value depends on the machine, so it is not asserted.
    _ = AXPermissionProbe(launchedAtLogin: false).isTrusted()
  }
}
