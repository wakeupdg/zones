import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ZonesCore
import os

// MARK: Error mapping (pure; tested without a live AX connection)

/// Raw `AXError` codes, kept as literals so tests need no `ApplicationServices` import.
enum AXCode {
  static let cannotComplete: Int32 = -25204
  static let invalidUIElement: Int32 = -25202
  static let apiDisabled: Int32 = -25211
  static let attributeUnsupported: Int32 = -25205
  static let noValue: Int32 = -25212
  static let failure: Int32 = -25200

  /// The attribute is not there (unsupported or empty); not an error for optional attributes.
  static func isAbsent(_ code: Int32) -> Bool { code == attributeUnsupported || code == noValue }
}

extension AXStatus {
  /// 0 is ok; CannotComplete is a timeout; InvalidUIElement is a gone element; APIDisabled is revocation.
  init(axErrorCode code: Int32) {
    switch code {
    case 0: self = .ok
    case AXCode.cannotComplete: self = .timedOut
    case AXCode.invalidUIElement: self = .elementGone
    case AXCode.apiDisabled: self = .apiDisabled
    default: self = .refused(code)
    }
  }
}

extension AXRead {
  /// The failure case for a non-zero `AXError` code. Code 0 is not a failure; it maps to `refused(0)`.
  static func failure(axErrorCode code: Int32) -> AXRead<T> {
    switch code {
    case AXCode.cannotComplete: .timedOut
    case AXCode.invalidUIElement: .elementGone
    case AXCode.apiDisabled: .apiDisabled
    default: .refused(code)
    }
  }
}

extension Subrole {
  /// Maps the AX subrole string (or, for sheets and popovers, the role string). Anything else is `unknown`.
  init(axSubrole: String?, axRole: String?) {
    switch axSubrole {
    case "AXStandardWindow": self = .standard
    case "AXDialog": self = .dialog
    case "AXSystemDialog": self = .systemDialog
    case "AXSystemFloatingWindow": self = .systemFloatingWindow
    case "AXFloatingWindow": self = .floating
    default:
      switch axRole {
      case "AXSheet": self = .sheet
      case "AXPopover": self = .popover
      default: self = .unknown
      }
    }
  }
}

/// The only callers of `CoordinateSpace.axRect` / `appKitRect` outside tests (AC-164).
enum AXGeometry {
  static func ax(_ appKit: CGRect, primaryFrame: CGRect) -> CGRect {
    CoordinateSpace.axRect(appKit, primaryFrame: primaryFrame)
  }

  static func appKit(_ ax: CGRect, primaryFrame: CGRect) -> CGRect {
    CoordinateSpace.appKitRect(ax, primaryFrame: primaryFrame)
  }
}

// MARK: Raw AX access (no policy; every call here is a single AX request)

private enum AXRaw {
  struct Copied {
    var code: Int32
    var value: CFTypeRef?
  }

  static func copy(_ element: AXUIElement, _ attribute: String) -> Copied {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return Copied(code: error.rawValue, value: error == .success ? value : nil)
  }

  static func string(_ value: CFTypeRef?) -> String? { value as? String }

  static func element(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
  }

  static func point(_ value: CFTypeRef?) -> CGPoint? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var out = CGPoint.zero
    return AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgPoint, &out) ? out : nil
  }

  static func size(_ value: CFTypeRef?) -> CGSize? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var out = CGSize.zero
    return AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgSize, &out) ? out : nil
  }

  /// The error code of a per-attribute failure inside a multiple-attribute read, if `value` is one.
  static func embeddedError(_ value: CFTypeRef) -> Int32? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .axError else { return nil }
    var error = AXError.success
    return AXValueGetValue(axValue, .axError, &error) ? error.rawValue : AXCode.failure
  }

  static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> AXStatus {
    AXStatus(axErrorCode: AXUIElementSetAttributeValue(element, attribute as CFString, value).rawValue)
  }

  static func isSettable(_ element: AXUIElement, _ attribute: String) -> AXRead<Bool> {
    var settable = DarwinBoolean(false)
    let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
    if error == .success { return .value(settable.boolValue) }
    if AXCode.isAbsent(error.rawValue) { return .value(false) }
    return .failure(axErrorCode: error.rawValue)
  }
}

// MARK: AXWindowSystem

/// The production `WindowSystem`. Every method runs on `WindowActor` (ADR-0015). It reports `timedOut` and never
/// loops on it: retry and cooldown policy belongs to the frame writer. No titles are read (LI-003).
public final class AXWindowSystem: WindowSystem {
  private static let enhancedUIAttribute = "AXEnhancedUserInterface"
  private static let fullScreenAttribute = "AXFullScreen"
  private static let maxClimb = 8

  private let primaryFrame: @Sendable () -> CGRect
  private let bridge: AXObserverBridge
  private let perAppTimeout = OSAllocatedUnfairLock(initialState: Constants.perAppTimeout)

  public init(primaryFrame: @escaping @Sendable () -> CGRect = { CGDisplayBounds(CGMainDisplayID()) }) {
    self.primaryFrame = primaryFrame
    self.bridge = AXObserverBridge()
  }

  // MARK: Timeouts

  /// `perApp` is applied to every element handed out afterwards; `processWide` goes on the system-wide element,
  /// which sets the process-wide default.
  @WindowActor public func setTimeouts(perApp: TimeInterval, processWide: TimeInterval) {
    perAppTimeout.withLock { $0 = perApp }
    _ = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Float(processWide))
  }

  private func applyTimeout(to element: AXUIElement) {
    let seconds = perAppTimeout.withLock { $0 }
    _ = AXUIElementSetMessagingTimeout(element, Float(seconds))
  }

  private func app(_ pid: pid_t) -> AXUIElement {
    let element = AXUIElementCreateApplication(pid)
    applyTimeout(to: element)
    return element
  }

  /// Every handle given out has the per-app timeout and a destroyed subscription.
  private func makeHandle(_ element: AXUIElement, pid: pid_t) -> WindowHandle {
    applyTimeout(to: element)
    let handle = WindowHandle(element: element, pid: pid)
    bridge.watch(handle)
    return handle
  }

  // MARK: Enumeration

  @WindowActor public func windows(of pid: pid_t) -> [WindowHandle] {
    let result = AXRaw.copy(app(pid), kAXWindowsAttribute)
    guard result.code == 0, let list = result.value as? [AnyObject] else { return [] }
    return list.compactMap { AXRaw.element($0) }.map { makeHandle($0, pid: pid) }
  }

  @WindowActor public func focusedWindow() -> WindowHandle? {
    let focusedApp = AXRaw.copy(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute)
    guard focusedApp.code == 0, let appElement = AXRaw.element(focusedApp.value) else { return nil }
    var pid: pid_t = 0
    guard AXUIElementGetPid(appElement, &pid) == .success else { return nil }
    applyTimeout(to: appElement)
    let window = AXRaw.copy(appElement, kAXFocusedWindowAttribute)
    guard window.code == 0, let element = AXRaw.element(window.value) else { return nil }
    return makeHandle(element, pid: pid)
  }

  /// Hit-tests the point (AppKit global). Climbs to the owning `AXWindow`; when that fails, falls back to the
  /// smallest window of the hit element's process that contains the point. Menu bar, Dock and desktop give nil.
  @WindowActor public func element(at point: CGPoint) -> WindowHandle? {
    let primary = primaryFrame()
    let axPoint = AXGeometry.ax(CGRect(origin: point, size: .zero), primaryFrame: primary).origin
    var hit: AXUIElement?
    let error = AXUIElementCopyElementAtPosition(
      AXUIElementCreateSystemWide(), Float(axPoint.x), Float(axPoint.y), &hit)
    guard error == .success, let hit else { return nil }
    var pid: pid_t = 0
    guard AXUIElementGetPid(hit, &pid) == .success else { return nil }
    applyTimeout(to: hit)
    let hitRole = AXRaw.string(AXRaw.copy(hit, kAXRoleAttribute).value)
    if Self.chromeRoles.contains(hitRole ?? "") || isDock(pid) { return nil }

    var current = hit
    for _ in 0..<Self.maxClimb {
      if AXRaw.string(AXRaw.copy(current, kAXRoleAttribute).value) == kAXWindowRole {
        return makeHandle(current, pid: pid)
      }
      let next = AXRaw.copy(current, kAXWindowAttribute)
      let parent = next.code == 0 ? next : AXRaw.copy(current, kAXParentAttribute)
      guard let up = AXRaw.element(parent.value) else { break }
      applyTimeout(to: up)
      current = up
    }
    return smallestWindow(of: pid, containing: point)
  }

  private static let chromeRoles: Set<String> = [
    kAXMenuBarRole, kAXMenuBarItemRole, kAXMenuRole, kAXMenuItemRole,
  ]

  private func isDock(_ pid: pid_t) -> Bool {
    NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock"
  }

  @WindowActor private func smallestWindow(of pid: pid_t, containing point: CGPoint) -> WindowHandle? {
    var best: (handle: WindowHandle, area: CGFloat)?
    for handle in windows(of: pid) {
      guard case .value(let rect) = frame(handle), rect.contains(point) else { continue }
      let area = rect.width * rect.height
      if area < (best?.area ?? .greatestFiniteMagnitude) { best = (handle, area) }
    }
    return best?.handle
  }

  // MARK: Reads

  @WindowActor public func frame(_ h: WindowHandle) -> AXRead<CGRect> {
    var values: CFArray?
    let names = [kAXPositionAttribute, kAXSizeAttribute] as CFArray
    let error = AXUIElementCopyMultipleAttributeValues(h.element, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
    guard error == .success else { return .failure(axErrorCode: error.rawValue) }
    guard let list = values as? [AnyObject], list.count == 2 else { return .refused(AXCode.failure) }
    for item in list {
      if let code = AXRaw.embeddedError(item) { return .failure(axErrorCode: code) }
    }
    guard let origin = AXRaw.point(list[0]), let size = AXRaw.size(list[1]) else {
      return .refused(AXCode.failure)
    }
    let ax = CGRect(origin: origin, size: size)
    return .value(AXGeometry.appKit(ax, primaryFrame: primaryFrame()))
  }

  /// One pass over many windows in a single `@WindowActor` turn. After a timeout for a pid, that pid's remaining
  /// handles are marked `timedOut` without another call: a hung app costs one timeout, not N.
  @WindowActor public func frames(_ hs: [WindowHandle]) -> [WindowKey: AXRead<CGRect>] {
    var out: [WindowKey: AXRead<CGRect>] = [:]
    var hung: Set<pid_t> = []
    for handle in hs {
      if hung.contains(handle.pid) {
        out[handle.key] = .timedOut
        continue
      }
      let read = frame(handle)
      if case .timedOut = read { hung.insert(handle.pid) }
      out[handle.key] = read
    }
    return out
  }

  @WindowActor public func facts(_ h: WindowHandle) -> AXRead<WindowFacts> {
    let role = AXRaw.copy(h.element, kAXRoleAttribute)
    if role.code != 0 && !AXCode.isAbsent(role.code) { return .failure(axErrorCode: role.code) }
    let subrole = AXRaw.copy(h.element, kAXSubroleAttribute)
    if subrole.code != 0 && !AXCode.isAbsent(subrole.code) { return .failure(axErrorCode: subrole.code) }
    let fullScreen = AXRaw.copy(h.element, Self.fullScreenAttribute)
    if fullScreen.code != 0 && !AXCode.isAbsent(fullScreen.code) { return .failure(axErrorCode: fullScreen.code) }
    let position = AXRaw.isSettable(h.element, kAXPositionAttribute)
    let size = AXRaw.isSettable(h.element, kAXSizeAttribute)
    guard case .value(let positionSettable) = position else { return failure(of: position) }
    guard case .value(let sizeSettable) = size else { return failure(of: size) }
    return .value(
      WindowFacts(
        subrole: Subrole(axSubrole: AXRaw.string(subrole.value), axRole: AXRaw.string(role.value)),
        isFullScreen: (fullScreen.value as? Bool) ?? false,
        positionSettable: positionSettable, sizeSettable: sizeSettable))
  }

  private func failure<A, B>(of read: AXRead<A>) -> AXRead<B> {
    switch read {
    case .value: .refused(AXCode.failure)
    case .timedOut: .timedOut
    case .elementGone: .elementGone
    case .apiDisabled: .apiDisabled
    case .refused(let code): .refused(code)
    }
  }

  // MARK: Writes

  /// `p` is the AppKit origin of the window rect. The current size is read to flip the origin into AX space.
  @WindowActor public func setPosition(_ p: CGPoint, _ h: WindowHandle) -> AXStatus {
    let sizeRead = AXRaw.copy(h.element, kAXSizeAttribute)
    guard sizeRead.code == 0 else { return AXStatus(axErrorCode: sizeRead.code) }
    guard let size = AXRaw.size(sizeRead.value) else { return .refused(AXCode.failure) }
    var origin = AXGeometry.ax(CGRect(origin: p, size: size), primaryFrame: primaryFrame()).origin
    guard let value = AXValueCreate(.cgPoint, &origin) else { return .refused(AXCode.failure) }
    return AXRaw.set(h.element, kAXPositionAttribute, value)
  }

  @WindowActor public func setSize(_ s: CGSize, _ h: WindowHandle) -> AXStatus {
    var size = s
    guard let value = AXValueCreate(.cgSize, &size) else { return .refused(AXCode.failure) }
    return AXRaw.set(h.element, kAXSizeAttribute, value)
  }

  // MARK: Enhanced UI (ADR-0022; the toggle policy lives in EnhancedUIRecovery)

  /// `.value(nil)` when the attribute is absent.
  @WindowActor public func enhancedUI(pid: pid_t) -> AXRead<Bool?> {
    let read = AXRaw.copy(app(pid), Self.enhancedUIAttribute)
    if read.code == 0 { return .value(read.value as? Bool) }
    if AXCode.isAbsent(read.code) { return .value(nil) }
    return .failure(axErrorCode: read.code)
  }

  @WindowActor public func setEnhancedUI(_ on: Bool, pid: pid_t) -> AXStatus {
    AXRaw.set(app(pid), Self.enhancedUIAttribute, on ? kCFBooleanTrue : kCFBooleanFalse)
  }

  // MARK: Heartbeat

  /// A real system-wide read, so revocation surfaces as `apiDisabled` (ADR-0021 amendment, SPK-006).
  @WindowActor public func trivialRead() -> AXStatus {
    let read = AXRaw.copy(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute)
    if read.code == 0 || read.code == AXCode.noValue { return .ok }
    return AXStatus(axErrorCode: read.code)
  }

  public func notices() -> AsyncStream<AXNotice> { bridge.notices() }
}
