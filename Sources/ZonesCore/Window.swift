import CoreGraphics
import Foundation

/// CGWindowID; session only.
public struct WindowID: Hashable, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
}

/// Phase-1 (CoreGraphics) facts. No titles, ever (LI-003).
public struct WindowRef: Hashable, Sendable {
  public var id: WindowID
  public var pid: pid_t
  public var bundleID: String?
  public var frame: CGRect
  public var layer: Int32
  public init(id: WindowID, pid: pid_t, bundleID: String?, frame: CGRect, layer: Int32) {
    self.id = id
    self.pid = pid
    self.bundleID = bundleID
    self.frame = frame
    self.layer = layer
  }
}

public enum Subrole: String, Sendable {
  case standard, dialog, systemDialog, systemFloatingWindow, floating, sheet, popover, unknown
}

/// Phase-2 (Accessibility) facts.
public struct WindowFacts: Hashable, Sendable {
  public var subrole: Subrole
  public var isFullScreen: Bool
  public var positionSettable: Bool
  public var sizeSettable: Bool
  public init(subrole: Subrole, isFullScreen: Bool, positionSettable: Bool, sizeSettable: Bool) {
    self.subrole = subrole
    self.isFullScreen = isFullScreen
    self.positionSettable = positionSettable
    self.sizeSettable = sizeSettable
  }
}

/// Registry key: the pid plus the CFHash of the Accessibility element.
public struct WindowKey: Hashable, Sendable {
  public var pid: pid_t
  public var elementHash: Int
  public init(pid: pid_t, elementHash: Int) {
    self.pid = pid
    self.elementHash = elementHash
  }
}

public enum CapturePath: String, Codable, Sendable { case mouse, keyboard }

public struct OriginalFrameEntry: Hashable, Sendable {
  public var key: WindowKey
  public var frame: CGRect
  public var via: CapturePath
  public init(key: WindowKey, frame: CGRect, via: CapturePath) {
    self.key = key
    self.frame = frame
    self.via = via
  }
}

public struct LastSnapRecord: Hashable, Sendable {
  public var key: WindowKey
  public var display: DisplayKey
  public var zones: Set<Int>
  public var frame: CGRect
  public init(key: WindowKey, display: DisplayKey, zones: Set<Int>, frame: CGRect) {
    self.key = key
    self.display = display
    self.zones = zones
    self.frame = frame
  }
}
