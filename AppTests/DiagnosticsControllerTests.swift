import Foundation
import Testing
import ZonesCore
import ZonesTestSupport
import ZonesWindowing

@testable import Zones

@MainActor
@Suite struct DiagnosticsControllerTests {
  @Test func previewBeforeCopy() {
    let h = Harness()
    let root = h.makeRoot()
    h.displays.enqueue(.snapshot(Fixtures.threeDisplays))
    root.topology.forceSnapshot()
    // A skip and a no-op leave log lines; none of them may carry a window title.
    Log.shared.skip(.systemDialog, ZonesCore.WindowRef(id: WindowID(rawValue: 5), pid: 12, bundleID: "com.example.secret", frame: .zero, layer: 0), category: .input)

    root.diagnostics.copyDiagnostics()
    #expect(h.diagnostics.calls.count == 2)
    guard case .preview(let shown) = h.diagnostics.calls.first, case .copy(let copied) = h.diagnostics.calls.last
    else {
      Issue.record("expected preview then copy, got \(h.diagnostics.calls)")
      return
    }
    #expect(shown == copied)
    #expect(shown.contains("version: 1.0"))
    #expect(shown.contains("displays: 3"))
    #expect(shown.contains("permission: notGranted"))
    #expect(!shown.lowercased().contains("title"))
  }

  @Test func declinedPreviewNeverCopies() {
    let h = Harness()
    h.diagnostics.confirm = false
    let root = h.makeRoot()
    root.diagnostics.copyDiagnostics()
    #expect(h.diagnostics.calls.count == 1)
    if case .preview = h.diagnostics.calls[0] {} else { Issue.record("expected only a preview") }
  }

  @Test func reportReflectsLiveState() {
    let h = Harness()
    let root = h.makeRoot()
    root.permission.receive(.probe(true))
    let report = root.diagnostics.report()
    #expect(report.permission == "granted")
    #expect(report.tap == "alive")
    #expect(report.preferences == root.state.preferences)
  }
}
