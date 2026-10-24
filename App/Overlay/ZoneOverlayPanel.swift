import AppKit

/// One click-through, never-key panel covering a whole Display (ADR-0023).
///
/// Shown only with `orderFrontRegardless()` and hidden with `orderOut(nil)`; it never becomes key or main and never
/// activates the app, so an armed Drag Session leaves the frontmost app and key window untouched (AC-044).
@MainActor
final class ZoneOverlayPanel: NSPanel {
  /// How many times `orderFrontRegardless()` ran. Tests read it; the presenter orders front once per session.
  private(set) var orderFrontCount = 0

  init(screenFrame: CGRect) {
    super.init(
      contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    isFloatingPanel = true  // resets `level`, so the level is set after it
    level = .screenSaver
    hidesOnDeactivate = false
    becomesKeyOnlyIfNeeded = true
    ignoresMouseEvents = true
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    animationBehavior = .none
    isReleasedWhenClosed = false
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  override func isAccessibilityElement() -> Bool { false }

  override func orderFrontRegardless() {
    orderFrontCount += 1
    super.orderFrontRegardless()
  }

  /// How many warm-up commits ran (`warmUp()`). Tests read it.
  private(set) var warmUpCount = 0

  /// Commits the layer tree once while fully transparent and then orders out again, so the window server holds a
  /// backing store and the glyphs are rasterized before the first real `orderFrontRegardless()` (AC-040). Does not
  /// count as an order front; the panel is hidden again before this returns.
  func warmUp() {
    warmUpCount += 1
    let alpha = alphaValue
    alphaValue = 0
    super.orderFrontRegardless()
    CATransaction.flush()
    orderOut(nil)
    alphaValue = alpha
  }

  /// Resizes to the Display's `screen.frame` without redrawing; the layer view re-applies its model afterwards.
  func fit(to screenFrame: CGRect) {
    guard frame != screenFrame else { return }
    setFrame(screenFrame, display: false)
  }
}
