/// The menu bar status item's look (AC-018): unbadged only while permission is granted and the tap is alive.
public struct StatusItemModel: Hashable, Sendable {
  public var badged: Bool
  /// Always true: the icon is a template image so the system tints it for the menu bar.
  public var isTemplate: Bool

  public init(badged: Bool, isTemplate: Bool = true) {
    self.badged = badged
    self.isTemplate = isTemplate
  }

  public static func derive(_ p: PermissionState, tap: TapState) -> StatusItemModel {
    StatusItemModel(badged: !(p == .granted && tap == .alive))
  }
}
