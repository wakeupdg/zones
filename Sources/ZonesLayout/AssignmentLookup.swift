import ZonesCore

/// Which Layout a Display shows. The session Assignment wins, then the persisted one, then Priority Grid.
/// An imported Assignment for a Display that is not connected yet stays in the one map (dormant) and is used the
/// first time its key is looked up.
public enum AssignmentLookup {
  public static func layoutID(
    for key: DisplayKey, in assignments: [String: Assignment], session: [DisplayKey: LayoutID]
  ) -> LayoutID {
    if let id = session[key] { return id }
    if case .uuid(let uuid) = key, let persisted = assignments[uuid] { return persisted.layout }
    return Templates.builtInID(.priorityGrid, count: 3)
  }
}
