import ApplicationServices
import AppKit
import Foundation

/// Spike-only: AX/CF reference types are not Sendable. The probe only ever hands them to the
/// observer thread once (setup) or reads them from main, so an unchecked box is acceptable.
struct UncheckedBox<T>: @unchecked Sendable {
  let value: T
}

/// Trivial read used as the heartbeat candidate (docs/CONTRACTS.md WindowSystem.trivialRead).
func trivialRead() -> (raw: Int32, status: AXStatus) {
  var v: CFTypeRef?
  let err = AXUIElementCopyAttributeValue(
    AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &v)
  return (err.rawValue, AXStatus(raw: err.rawValue))
}

func appElement(pid: pid_t) -> AXUIElement {
  let app = AXUIElementCreateApplication(pid)
  AXUIElementSetMessagingTimeout(app, 0.25)  // ADR-0015: 250 ms messaging timeout
  return app
}

func firstWindow(of app: AXUIElement, front: Bool = true) -> AXUIElement? {
  var v: CFTypeRef?
  if front,
    AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &v) == .success,
    let v, CFGetTypeID(v) == AXUIElementGetTypeID()
  {
    return (v as! AXUIElement)  // CFTypeID checked above
  }
  v = nil
  guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success,
    let list = v as? [AXUIElement], let first = list.first
  else { return nil }
  return first
}

func windowPosition(_ win: AXUIElement) -> CGPoint? {
  var v: CFTypeRef?
  guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &v) == .success,
    let v, CFGetTypeID(v) == AXValueGetTypeID()
  else { return nil }
  var p = CGPoint.zero
  return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil  // CFTypeID checked above
}

@discardableResult
func setWindowPosition(_ win: AXUIElement, _ p: CGPoint) -> AXError {
  var pt = p
  guard let val = AXValueCreate(.cgPoint, &pt) else { return .failure }
  return AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, val)
}

func runningPID(bundleID: String) -> pid_t? {
  NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
}

/// Handler target for the C observer callback. Spike-only: `handler` is set before the
/// observer source is scheduled and never mutated, so unchecked Sendable is sound.
final class AXWatch: @unchecked Sendable {
  let handler: @Sendable (_ notification: String, _ element: AXUIElement) -> Void
  init(handler: @escaping @Sendable (String, AXUIElement) -> Void) { self.handler = handler }
}

let axObserverCallback: AXObserverCallback = { _, element, notification, refcon in
  guard let refcon else { return }
  Unmanaged<AXWatch>.fromOpaque(refcon).takeUnretainedValue().handler(notification as String, element)
}

/// Creates an observer for `pid`. The returned source is NOT yet added to any run loop.
func makeObserver(pid: pid_t) -> AXObserver? {
  var obs: AXObserver?
  let err = AXObserverCreate(pid, axObserverCallback, &obs)
  if err != .success {
    probeLog.emit(["event": "observerCreate", "raw": Int(err.rawValue), "name": rawAXErrorName(err.rawValue)])
    return nil
  }
  return obs
}

/// Registers a notification and logs the raw result (alreadyRegistered/unsupported are informative).
@discardableResult
func addNotification(
  _ obs: AXObserver, _ element: AXUIElement, _ name: String, _ watch: AXWatch, label: String
) -> AXError {
  let err = AXObserverAddNotification(
    obs, element, name as CFString, Unmanaged.passUnretained(watch).toOpaque())
  probeLog.emit([
    "event": "addNotification", "notification": name, "element": label,
    "raw": Int(err.rawValue), "name": rawAXErrorName(err.rawValue),
  ])
  return err
}
