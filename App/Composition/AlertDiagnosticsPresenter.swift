import AppKit

/// Shows the report in a scrolling alert first; Copy puts it on the pasteboard, Cancel does nothing (AC-154).
@MainActor
final class AlertDiagnosticsPresenter: DiagnosticsPresenter {
  func showPreview(_ text: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = "Copy Diagnostics"
    alert.informativeText = "This is exactly what will be copied. It contains no window titles."
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 300))
    scroll.hasVerticalScroller = true
    let view = NSTextView(frame: scroll.bounds)
    view.isEditable = false
    view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    view.string = text
    scroll.documentView = view
    alert.accessoryView = scroll
    alert.addButton(withTitle: "Copy")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn
  }

  func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}
