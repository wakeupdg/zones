import Foundation
import ZonesCore

public enum RawDisplayChange: Hashable, Sendable { case reconfiguration, screenParameters, activeSpace, wake }

/// Production: ScreenDisplayProvider. Fake: FakeDisplayProvider.
public protocol DisplayProvider: Sendable {
  func snapshot() -> TopologySnapshot
  var changes: AsyncStream<RawDisplayChange> { get }
}
