import Foundation
import ZonesCore
import ZonesLayout

/// Per-Layout and per-Display actions (US-096, US-099, AC-115). Each runs on a copy, persists through
/// `DocumentStore`, and replaces the state only after the write succeeds; a refusal sets `actionError`.
extension LayoutsFlow {
  public typealias ActionResult = Result<Void, DocumentError>

  /// Adds a custom copy of any Layout (built-in or custom) named "<name> copy", "<name> copy 2", ...
  @discardableResult
  public mutating func duplicate(
    _ id: LayoutID, newID: () -> LayoutID = { LayoutID(rawValue: UUID().uuidString) }
  ) -> Result<LayoutID, DocumentError> {
    guard let source = store.layout(id) else { return fail(.io("no layout with id \(id.rawValue)")) }
    var copy = source
    copy.id = newID()
    copy.builtIn = nil
    copy.name = Self.uniqueName("\(source.name) copy", among: Set(allNames))
    var next = store
    next.upsert(copy)
    return commit(layouts: next, assignments: assignments, session: session).map { copy.id }
  }

  /// Renames a custom Layout. A blank name or a built-in is refused.
  @discardableResult
  public mutating func rename(_ id: LayoutID, to name: String) -> ActionResult {
    guard var layout = store.custom.first(where: { $0.id == id }) else {
      return fail(.io("only custom layouts can be renamed"))
    }
    layout.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if let fault = LayoutValidator.validate(layout) { return fail(.invalidLayout(name: name, fault)) }
    var next = store
    next.upsert(layout)
    return commit(layouts: next, assignments: assignments, session: session)
  }

  /// True when any stored Assignment or session pick uses the Layout.
  public func isInUse(_ id: LayoutID) -> Bool {
    assignments.values.contains { $0.layout == id } || session.values.contains(id)
  }

  /// Deletes a custom Layout. A Layout in use needs a `replacement`, which every user is moved to.
  @discardableResult
  public mutating func delete(_ id: LayoutID, replacement: LayoutID?) -> ActionResult {
    var next = store
    var nextAssignments = assignments
    var nextSession = session
    if isInUse(id), replacement == nil {
      return fail(.io("layout is assigned to a Display; choose a replacement"))
    }
    if case .failure(let error) = next.delete(id, replacement: replacement, assignments: &nextAssignments) {
      return fail(error)
    }
    if let replacement {
      for (key, value) in nextSession where value == id { nextSession[key] = replacement }
    }
    return commit(layouts: next, assignments: nextAssignments, session: nextSession)
  }

  /// "Copy Assignment to <attached>": the stored record of a disconnected Display is copied to an attached
  /// Display with a persistable key. The record takes the target's name, frame and scale.
  @discardableResult
  public mutating func copyAssignment(from key: String, to target: DisplaySnapshot) -> ActionResult {
    guard let source = assignments[key] else { return fail(.io("no stored Assignment for that Display")) }
    guard case .uuid(let uuid) = target.key else { return fail(.io("\(target.name) has no stable identity")) }
    var next = assignments
    next[uuid] = Assignment(
      layout: source.layout, displayName: target.name, lastVisibleFrame: target.visibleFrame, lastScale: target.scale,
      lastSeen: nil)
    return commit(layouts: store, assignments: next, session: session)
  }

  /// "Forget": removes the stored record of a Display.
  @discardableResult
  public mutating func forget(_ key: String) -> ActionResult {
    guard assignments[key] != nil else { return fail(.io("no stored Assignment for that Display")) }
    var next = assignments
    next[key] = nil
    return commit(layouts: store, assignments: next, session: session)
  }

  /// The Layout picker for an attached Display. A persistable key writes the Assignment; an unstable key
  /// ("not saved") is kept for this session only and never touches the disk.
  @discardableResult
  public mutating func pick(_ layout: LayoutID, for display: DisplaySnapshot) -> ActionResult {
    guard store.layout(layout) != nil else { return fail(.io("no layout with id \(layout.rawValue)")) }
    switch display.key {
    case .unstable:
      session[display.key] = layout
      actionError = nil
      return .success(())
    case .uuid(let uuid):
      var next = assignments
      if var existing = next[uuid] {
        existing.layout = layout
        existing.displayName = display.name
        next[uuid] = existing
      } else {
        next[uuid] = Assignment(
          layout: layout, displayName: display.name, lastVisibleFrame: display.visibleFrame, lastScale: display.scale,
          lastSeen: nil)
      }
      return commit(layouts: store, assignments: next, session: session)
    }
  }

  /// Changing the default Margin and Gap regenerates the built-ins (AC-117); custom Layouts keep their own.
  public mutating func setDefaultInsets(_ insets: Insets) {
    defaults = insets
    store.setDefaults(insets)
  }

  // MARK: Helpers

  private var allNames: [String] { (store.builtIns + store.custom).map(\.name) }

  static func uniqueName(_ name: String, among taken: Set<String>) -> String {
    guard taken.contains(name) else { return name }
    var n = 2
    while taken.contains("\(name) \(n)") { n += 1 }
    return "\(name) \(n)"
  }

  private mutating func fail<T>(_ error: DocumentError) -> Result<T, DocumentError> {
    actionError = error.importText
    return .failure(error)
  }

  /// Writes only what changed, then swaps the state in. On a write failure the state and files stay as they were.
  private mutating func commit(
    layouts: LayoutStore, assignments next: [String: Assignment], session nextSession: [DisplayKey: LayoutID]
  ) -> ActionResult {
    do throws(DocumentError) {
      if layouts.custom != store.custom { try documents.save(layouts.document, as: .layouts) }
      if next != assignments {
        do throws(DocumentError) {
          try documents.save(ZonesDocument(assignments: next), as: .assignments)
        } catch {
          if layouts.custom != store.custom { try? documents.save(store.document, as: .layouts) }
          throw error
        }
      }
    } catch {
      return fail(error)
    }
    store = layouts
    assignments = next
    session = nextSession
    actionError = nil
    return .success(())
  }
}
