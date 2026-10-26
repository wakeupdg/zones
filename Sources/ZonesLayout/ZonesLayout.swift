/// Result of a hit test; the pure `HitTest` function is added by its owning ticket.
public enum Hit: Hashable, Sendable { case zone(Int), nearest(Int), none }
