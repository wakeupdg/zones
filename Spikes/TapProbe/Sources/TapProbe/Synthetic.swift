import CoreGraphics
import Foundation

/// Optional self-test: posts a synthetic Shift flagsChanged down and up. Never posts mouse events,
/// so it cannot click or drag anything on the host. Output is labelled SYNTHETIC by the caller.
enum Synthetic {
  static func shiftTap() {
    for flags in [CGEventFlags.maskShift, CGEventFlags()] {
      guard let event = CGEvent(source: CGEventSource(stateID: .combinedSessionState)) else { continue }
      event.type = .flagsChanged
      event.flags = flags
      event.setIntegerValueField(.keyboardEventKeycode, value: 56)
      event.post(tap: .cgSessionEventTap)
      Thread.sleep(forTimeInterval: 0.1)
    }
  }
}
