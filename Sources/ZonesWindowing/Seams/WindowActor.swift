/// ADR-0015: every Accessibility call runs on this actor; UI runs on the main actor.
@globalActor public actor WindowActor {
  public static let shared = WindowActor()
}
