import ApplicationServices
import Foundation
import Testing
import ZonesCore
import ZonesWindowing

private func requireSendable<T: Sendable>(_: T.Type) {}

@Test func seamProtocolsAreSendable() {
  requireSendable((any WindowSystem).self)
  requireSendable((any WindowEnumerator).self)
  requireSendable((any InputSource).self)
  requireSendable((any DisplayProvider).self)
  requireSendable((any OverlayPresenter).self)
  requireSendable((any HotkeyRegistrar).self)
  requireSendable((any LoginItemService).self)
  requireSendable((any PermissionProbe).self)
  requireSendable((any Clock).self)
}

@Test func windowHandleEqualityUsesKey() {
  let pid = getpid()
  let a = WindowHandle(element: AXUIElementCreateApplication(pid), pid: pid)
  let b = WindowHandle(element: AXUIElementCreateApplication(pid), pid: pid)
  #expect(a == b)
  #expect(a.hashValue == b.hashValue)
  #expect(a.key == b.key)
  #expect(a.key.pid == pid)
}

@Test func tapConfigProductionIsListenOnly() {
  #expect(TapConfig.production.listenOnly)
  #expect(TapConfig.production.mask == [.leftDown, .leftDragged, .leftUp, .flagsChanged])
}

@Test func uncheckedBoxCountIsOne() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let needle = "@unchecked" + " Sendable"
  var hits: [String] = []
  for dir in ["Sources", "App"] {
    let base = root.appendingPathComponent(dir)
    guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
      continue
    }
    for case let url as URL in walker where url.pathExtension == "swift" {
      let text = try String(contentsOf: url, encoding: .utf8)
      for line in text.split(separator: "\n", omittingEmptySubsequences: false) where line.contains(needle) {
        hits.append(url.path)
      }
    }
  }
  #expect(hits.count == 1)
  #expect(hits.first?.contains("/Sources/ZonesWindowing/") == true)
}
