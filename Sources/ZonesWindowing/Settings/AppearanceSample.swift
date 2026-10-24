import Foundation
import ZonesCore
import ZonesLayout

/// The Appearance pane's live sample caption: which Layouts follow the default Margin and Gap (US-117).
/// The set comes from `AppearancePaneModel.followers`; this only attaches names.
public struct AppearanceSample: Hashable, Sendable {
  public var followerIDs: [LayoutID]
  /// Names of every follower, in `followerIDs` order.
  public var names: [String]
  public var builtInCount: Int
  /// Followers that are custom Layouts, in order.
  public var customNames: [String]

  public init(defaults: Insets, store: LayoutStore) {
    let layouts = store.builtIns + store.custom
    followerIDs = AppearancePaneModel.followers(of: defaults, in: layouts)
    let byID = Dictionary(layouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let followers = followerIDs.compactMap { byID[$0] }
    names = followers.map(\.name)
    builtInCount = followers.filter { $0.builtIn != nil }.count
    customNames = followers.filter { $0.builtIn == nil }.map(\.name)
  }

  /// "All 12 built-in Layouts, Desk, Wall" style summary for the sample caption.
  public var summary: String {
    var parts: [String] = []
    if builtInCount > 0 { parts.append(builtInCount == 1 ? "1 built-in Layout" : "All \(builtInCount) built-in Layouts") }
    parts += customNames
    return parts.isEmpty ? "No Layouts" : parts.joined(separator: ", ")
  }
}
