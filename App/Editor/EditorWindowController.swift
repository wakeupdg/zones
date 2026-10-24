import AppKit
import ZonesCore
import ZonesWindowing

/// Owns the layout editor's `NSWindow`. The editor is an ordinary key-capable window (ADR-0023), not the overlay panel.
@MainActor
final class EditorWindowController {
  /// Backdrop alpha: low enough that the desktop windows behind stay visible (AC-126); no blur.
  nonisolated static let backdropAlpha: CGFloat = 0.25

  /// The window opens on the cursor Display's visible frame (AC-022), resizable, over a translucent backdrop.
  static func makeWindow(display: DisplaySnapshot) -> NSWindow {
    let frame = WindowPlacement.editorFrame(cursor: display)
    // Raw style bits come from Shell (AppKit-free); `.fullSizeContentView` lets the canvas fill the whole frame so
    // the Zones cover exactly the screen area the Overlay highlights.
    let mask = NSWindow.StyleMask(rawValue: WindowPlacement.editorStyleMaskRaw).union(.fullSizeContentView)
    let window = NSWindow(contentRect: frame, styleMask: mask, backing: .buffered, defer: false)
    window.title = "Zones Layout Editor"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = NSColor.black.withAlphaComponent(backdropAlpha)
    window.hasShadow = false
    window.collectionBehavior = [.moveToActiveSpace]
    window.setFrame(frame, display: false)
    return window
  }
}
