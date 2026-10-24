import Foundation
import ZonesCore

/// Once per (bundleID, pid, launchDate) per session (AC-076). Stub: T19 fills the logic; only the
/// signature `FrameWriter` needs exists here.
public struct EnhancedUIRecovery: Sendable {
  let store: DocumentStore

  public init(store: DocumentStore) { self.store = store }

  public func noteIfFirst(_ record: RecoveryRecord) {}
}
