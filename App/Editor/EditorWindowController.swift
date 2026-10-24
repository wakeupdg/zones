import AppKit
import ZonesCore
import ZonesLayout
import ZonesWindowing

/// Owns the layout editor's `NSWindow`. The editor is an ordinary key-capable window (ADR-0023), not the overlay panel.
@MainActor
final class EditorWindowController: EditorEffectSink {
  /// Backdrop alpha: low enough that the desktop windows behind stay visible (AC-126); no blur.
  nonisolated static let backdropAlpha: CGFloat = 0.25

  /// The window opens on the cursor Display's visible frame (AC-022), resizable, over a translucent backdrop.
  static func makeWindow(display: DisplaySnapshot) -> EditorWindow {
    let frame = WindowPlacement.editorFrame(cursor: display)
    // Raw style bits come from Shell (AppKit-free); `.fullSizeContentView` lets the canvas fill the whole frame so
    // the Zones cover exactly the screen area the Overlay highlights.
    let mask = NSWindow.StyleMask(rawValue: WindowPlacement.editorStyleMaskRaw).union(.fullSizeContentView)
    let window = EditorWindow(contentRect: frame, styleMask: mask, backing: .buffered, defer: false)
    window.title = "Zones Layout Editor"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = NSColor.black.withAlphaComponent(backdropAlpha)
    window.hasShadow = false
    window.collectionBehavior = [.moveToActiveSpace]
    window.setFrame(frame, display: false)
    return window
  }

  // MARK: session

  private let topology: () -> TopologySnapshot?
  private let cursor: () -> CGPoint
  private let store: DocumentStore
  private let loadDocument: () -> ZonesDocument
  private let documentChanged: (ZonesDocument) -> Void
  private let upsertLive: (Layout) -> Void
  private let appearance: () -> Appearance

  private var window: EditorWindow?
  private var canvas: EditorCanvasView?
  private var toolbar: EditorToolbarView?
  private var closeObserver: (any NSObjectProtocol)?
  private var router: EditorEffectRouter?
  private var state: EditorState?
  private var document = ZonesDocument()
  private var lastTopology: TopologySnapshot?
  private var lastMessage: String?

  /// `store` and `loadDocument` are the app's `DocumentStore` and its current in-memory document;
  /// `documentChanged` receives the document after each write, and `upsertLive` is the live
  /// `LayoutStore.upsert`. The caller owns all of them; the editor consumes them.
  init(
    topology: @escaping () -> TopologySnapshot?, cursor: @escaping () -> CGPoint, store: DocumentStore,
    loadDocument: @escaping () -> ZonesDocument, documentChanged: @escaping (ZonesDocument) -> Void,
    upsertLive: @escaping (Layout) -> Void, appearance: @escaping () -> Appearance
  ) {
    self.topology = topology
    self.cursor = cursor
    self.store = store
    self.loadDocument = loadDocument
    self.documentChanged = documentChanged
    self.upsertLive = upsertLive
    self.appearance = appearance
  }

  var isOpen: Bool { window != nil }

  /// Opens the editor on the Display under the cursor, editing `layout`. A built-in is edited as a custom copy
  /// (built-ins are never persisted). Re-opening while open replaces the session.
  func show(layout: Layout) {
    guard let snapshot = topology(), let display = WindowPlacement.cursorDisplay(cursor: cursor(), in: snapshot)
    else { return }
    closeSession()
    lastTopology = snapshot
    document = loadDocument()

    let editable =
      layout.builtIn == nil
      ? layout
      : Templates.duplicate(layout, insets: layout.insets, newID: LayoutID(rawValue: UUID().uuidString))
    var opened = EditorModel.open(editable, display: display.key, topology: snapshot, assignments: document.assignments)
    // A lone Zone starts selected so H and V work with the first keystroke (AC-139). Direct assignment keeps it
    // out of the undo stack.
    if editable.root == .leaf { opened.draft.selection = NodePath(steps: []) }
    state = opened

    let window = Self.makeWindow(display: display)
    let canvas = EditorCanvasView(zoneStyle: appearance())
    let toolbar = EditorToolbarView()
    let container = NSView()
    for view in [canvas, toolbar] as [NSView] {
      view.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(view)
    }
    NSLayoutConstraint.activate([
      canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      canvas.topAnchor.constraint(equalTo: container.topAnchor),
      canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      toolbar.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      toolbar.topAnchor.constraint(equalTo: container.topAnchor, constant: 34),
      toolbar.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 8),
      toolbar.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
    ])
    window.contentView = container

    canvas.onEvent = { [weak self] in self?.send($0) }
    toolbar.onEvent = { [weak self] in self?.send($0) }
    toolbar.onSaveAndClose = { [weak self] in self?.saveAndClose() }
    window.onEvent = { [weak self] in self?.send($0) }
    window.selection = { [weak self] in self?.state?.draft.selection }

    router = EditorEffectRouter(
      store: store, sink: self, topology: { [weak self] in self?.currentTopology() ?? snapshot },
      upsertLive: upsertLive)
    closeObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.sessionEnded() } }

    self.window = window
    self.canvas = canvas
    self.toolbar = toolbar
    refresh()
    // An accessory app is not active by default and an inactive window is never key (ADR-0019).
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(canvas)
  }

  /// Feeds one event through the reducer and interprets the effects.
  func send(_ event: EditorEvent) {
    guard let current = state, let router else { return }
    lastMessage = nil
    let (next, effects) = EditorModel.reduce(current, event, context: (currentTopology(), document))
    state = next
    if next.display != current.display, let snapshot = currentTopology().display(next.display) {
      // Follow a connected Display so the Zones sit over the screen they describe.
      window?.setFrame(WindowPlacement.editorFrame(cursor: snapshot), display: true)
    }
    let written = router.route(effects, document: document)
    if written != document {
      document = written
      documentChanged(written)
    }
    refresh()
  }

  /// Save, then close unless the save was refused.
  func saveAndClose() {
    send(.save)
    if lastMessage == nil { send(.cancel) }
  }

  private func currentTopology() -> TopologySnapshot {
    if let live = topology() { lastTopology = live }
    return lastTopology ?? TopologySnapshot(displays: [], separateSpaces: true, primaryFrame: .zero)
  }

  private func refresh() {
    guard let state else { return }
    canvas?.zoneStyle = appearance()
    canvas?.state = state
    toolbar?.update(state: state, topology: currentTopology(), assignments: document.assignments)
    toolbar?.show(message: lastMessage ?? "")
  }

  // MARK: EditorEffectSink

  func showUnsavedPrompt(switchingTo key: DisplayKey) {
    guard let window else { return }
    let alert = NSAlert()
    alert.messageText = "Switch Display with unsaved changes?"
    alert.informativeText = "Your draft carries over to the other Display. It is not saved until you press Save."
    alert.addButton(withTitle: "Switch")
    alert.addButton(withTitle: "Cancel")
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertFirstButtonReturn else { return }
      MainActor.assumeIsolated { self?.send(EditorToolbarModel.confirmSwitch(to: key)) }
    }
  }

  func showMessage(_ text: String) {
    lastMessage = text
    toolbar?.show(message: text)
  }

  func closeEditor() { window?.close() }

  // MARK: teardown

  private func closeSession() {
    let old = window
    sessionEnded()
    old?.close()
  }

  private func sessionEnded() {
    if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    closeObserver = nil
    window = nil
    canvas = nil
    toolbar = nil
    router = nil
    state = nil
  }
}
