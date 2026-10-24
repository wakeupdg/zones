import CoreGraphics

public enum NoOpReason: String, Codable, Sendable {
  case sameFrame, zoneAbsent, noEntry, fullScreen, excluded, positionNotSettable, windowAbsent, notIdle
}

public enum FrameWriteResult: Hashable, Sendable {
  case applied(CGRect), clamped(CGRect), refused(Int32), timedOut, elementGone, noOp(NoOpReason)
}

public enum AXStatus: Hashable, Sendable { case ok, timedOut, elementGone, apiDisabled, refused(Int32) }

public enum AXRead<T: Sendable>: Sendable {
  case value(T), timedOut, elementGone, apiDisabled, refused(Int32)
}

// Conditional, so `AXRead<CGRect>` can appear in seam signatures: CGRect is Hashable only from macOS 15.
extension AXRead: Equatable where T: Equatable {}
extension AXRead: Hashable where T: Hashable {}

public enum SkipReason: String, Codable, CaseIterable, Sendable {
  // Phase 1
  case ownProcess, systemAgent, excludedBundle, unresponsive, ambiguousMatch
  // Phase 2
  case nonStandardSubrole, sheetOrPopover, systemDialog, fullScreen, positionNotSettable
}

public enum SnapMode: String, Codable, Sendable { case full, positionOnly }

public enum Verdict: Hashable, Sendable { case allow(SnapMode), skip(SkipReason) }

public enum LayoutFault: Hashable, Sendable {
  case ratioOutOfRange(NodePath), leafTooSmall(NodePath), surroundOutOfRange, overlap, emptyName
}

public enum DocumentError: Error, Hashable, Sendable {
  case corrupt(String), newerVersion(found: Int, supported: Int), invalidLayout(name: String, LayoutFault),
    nonUUIDKey(String), io(String)
}

public enum EditorError: Error, Hashable, Sendable {
  case notSiblings(hint: String), tooSmall, rootMerge, invalidRatio, nothingSelected
}

public enum LoginItemError: Error, Hashable, Sendable { case launchDeniedByUser, invalidSignature, other(String) }
