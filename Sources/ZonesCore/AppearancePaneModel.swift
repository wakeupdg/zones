/// Logic behind the Appearance pane's sample: which Layouts follow the default Margin and Gap.
public struct AppearancePaneModel {
  /// A Layout follows the defaults when it is a built-in (built-ins always use them) or its Insets equal
  /// `defaults`. Order follows `layouts`.
  public static func followers(of defaults: Insets, in layouts: [Layout]) -> [LayoutID] {
    layouts.filter { $0.builtIn != nil || $0.insets == defaults }.map(\.id)
  }
}
