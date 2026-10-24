import SwiftUI
import ZonesCore
import ZonesLayout
import ZonesWindowing

/// Layouts: one row per Display (attached, then disconnected), the Layout list with Duplicate, Rename and
/// Delete, and Import and Export. Every decision comes from `LayoutsPaneModel` and `LayoutsFlow`.
struct LayoutsPane: View {
  let controller: ImportExportController
  let topology: () -> TopologySnapshot?

  @State private var renaming: LayoutID?
  @State private var renameText = ""
  @State private var deleting: LayoutID?
  @State private var replacement: LayoutID?

  private struct DisplayItem: Identifiable {
    var id: String
    var row: LayoutsPaneModel.Row
  }

  var body: some View {
    let flow = controller.flow
    let snapshot = topology() ?? TopologySnapshot(displays: [], separateSpaces: true, primaryFrame: .zero)
    let items = LayoutsPaneModel.rows(snapshot, assignments: flow.assignments, session: flow.session).map { row in
      switch row {
      case .attached(let display, _, _): DisplayItem(id: "attached:\(display.key)", row: row)
      case .disconnected(let key, _, _): DisplayItem(id: "disconnected:\(key)", row: row)
      }
    }
    let layouts = flow.store.builtIns + flow.store.custom
    Form {
      Section("Displays") {
        if items.isEmpty { Text("No Displays found.").foregroundStyle(.secondary) }
        ForEach(items) { item in
          switch item.row {
          case .attached(let display, let layoutID, let unstable):
            attachedRow(display, layoutID: layoutID, unstable: unstable, layouts: layouts)
          case .disconnected(let key, let assignment, let targets):
            disconnectedRow(key, assignment: assignment, targets: targets, snapshot: snapshot, flow: flow)
          }
        }
      }
      Section("Layouts") {
        ForEach(layouts) { layout in layoutRow(layout) }
      }
      Section("Import and export") {
        HStack {
          Button("Export all…") { controller.exportAll() }
          Button("Import…") { controller.startImport() }
        }
        if let status = controller.exportStatus { Text(status).font(.callout).foregroundStyle(.secondary) }
        if let error = flow.importError {
          Text(error).font(.callout).foregroundStyle(.red).accessibilityLabel("Import error: \(error)")
        }
        if let report = flow.lastImport, flow.importError == nil { Text(Self.summary(report)).font(.callout) }
      }
      if let error = flow.actionError {
        Section { Text(error).foregroundStyle(.red) }
      }
    }
    .formStyle(.grouped)
    .sheet(item: $renaming.asIdentifiable) { item in renameSheet(item.id) }
    .sheet(item: $deleting.asIdentifiable) { item in deleteSheet(item.id) }
    .sheet(isPresented: Binding(get: { flow.pendingImport != nil }, set: { if !$0 { controller.cancelImport() } })) {
      importSheet()
    }
  }

  // MARK: Rows

  private func attachedRow(_ display: DisplaySnapshot, layoutID: LayoutID, unstable: Bool, layouts: [ZonesCore.Layout])
    -> some View
  {
    LabeledContent {
      HStack {
        if unstable {
          Text(LayoutsPaneModel.notSavedLabel).font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color(nsColor: .quaternarySystemFill)))
        }
        Picker("Layout for \(display.name)", selection: Binding(get: { layoutID }, set: { controller.pick($0, for: display) })) {
          ForEach(layouts) { Text($0.pickerTitle).tag($0.id) }
        }
        .labelsHidden()
        .fixedSize()
      }
    } label: {
      VStack(alignment: .leading) {
        Text(display.name)
        Text("\(Int(display.resolution.width)) × \(Int(display.resolution.height))")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func disconnectedRow(
    _ key: String, assignment: Assignment, targets: [DisplayKey], snapshot: TopologySnapshot, flow: LayoutsFlow
  ) -> some View {
    LabeledContent {
      HStack {
        Text(flow.store.layout(assignment.layout)?.pickerTitle ?? assignment.layout.rawValue).foregroundStyle(.secondary)
        Menu("Copy Assignment") {
          ForEach(targets.compactMap { snapshot.display($0) }, id: \.key) { target in
            Button(LayoutsPaneModel.copyTitle(target)) { controller.copyAssignment(from: key, to: target) }
          }
        }
        .disabled(targets.isEmpty)
        .fixedSize()
        Button(LayoutsPaneModel.forgetTitle, role: .destructive) { controller.forget(key) }
      }
    } label: {
      VStack(alignment: .leading) {
        Text(assignment.displayName)
        Text("Not connected").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func layoutRow(_ layout: ZonesCore.Layout) -> some View {
    let isCustom = layout.builtIn == nil
    return LabeledContent {
      HStack {
        Button("Duplicate") { controller.duplicate(layout.id) }
        if isCustom {
          Button("Rename…") {
            renameText = layout.name
            renaming = layout.id
          }
          Button("Export…") { controller.export(layout: layout.id) }
          Button("Delete…", role: .destructive) {
            replacement = nil
            deleting = layout.id
          }
        }
      }
    } label: {
      Text(layout.pickerTitle)
    }
  }

  // MARK: Sheets

  private func renameSheet(_ id: LayoutID) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Rename Layout").font(.headline)
      TextField("Name", text: $renameText).frame(minWidth: 240)
      HStack {
        Spacer()
        Button("Cancel") { renaming = nil }.keyboardShortcut(.cancelAction)
        Button("Rename") {
          if controller.rename(id, to: renameText) { renaming = nil }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
  }

  private func deleteSheet(_ id: LayoutID) -> some View {
    let flow = controller.flow
    let name = flow.store.layout(id)?.pickerTitle ?? "Layout"
    let inUse = flow.isInUse(id)
    let choices = (flow.store.builtIns + flow.store.custom).filter { $0.id != id }
    return VStack(alignment: .leading, spacing: 12) {
      Text("Delete \(name)?").font(.headline)
      if inUse {
        Text("A Display uses this Layout. Choose the Layout those Displays should use instead.")
          .foregroundStyle(.secondary)
        Picker("Replacement", selection: $replacement) {
          Text("Choose…").tag(LayoutID?.none)
          ForEach(choices) { Text($0.pickerTitle).tag(LayoutID?.some($0.id)) }
        }
      }
      HStack {
        Spacer()
        Button("Cancel") { deleting = nil }.keyboardShortcut(.cancelAction)
        Button("Delete", role: .destructive) {
          if controller.delete(id, replacement: replacement) { deleting = nil }
        }
        .disabled(inUse && replacement == nil)
      }
    }
    .padding(20)
    .frame(minWidth: 320)
  }

  private func importSheet() -> some View {
    ImportSheet(controller: controller)
  }

  private static func summary(_ report: ImportReport) -> String {
    var text = report.mode == .merge ? "Merged." : "Replaced."
    if let backup = report.backup { text += " Backup: \(backup)." }
    if !report.dormant.isEmpty {
      text += " \(report.dormant.count) imported Display\(report.dormant.count == 1 ? " is" : "s are") not connected and kept for later."
    }
    return text
  }
}

/// The one Merge or Replace choice per file. Replace names the backup it will write.
struct ImportSheet: View {
  let controller: ImportExportController
  @State private var mode: ImportMode = .merge

  var body: some View {
    let flow = controller.flow
    VStack(alignment: .leading, spacing: 12) {
      Text("Import \(flow.pendingImport?.fileName ?? "file")").font(.headline)
      Picker("Mode", selection: $mode) {
        Text("Merge: keep my Layouts and add these").tag(ImportMode.merge)
        Text("Replace: use only what is in this file").tag(ImportMode.replace)
      }
      .pickerStyle(.radioGroup)
      .labelsHidden()
      if mode == .replace, let backup = controller.replaceBackupName {
        Text("Your current Layouts and Assignments are saved as \(backup) first.")
          .font(.callout).foregroundStyle(.secondary)
      }
      if let error = flow.importError { Text(error).font(.callout).foregroundStyle(.red) }
      HStack {
        Spacer()
        Button("Cancel") { controller.cancelImport() }.keyboardShortcut(.cancelAction)
        Button("Import") { controller.applyImport(mode) }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(minWidth: 380)
  }
}

private struct IdentifiedLayout: Identifiable { var id: LayoutID }

extension Binding where Value == LayoutID? {
  /// `.sheet(item:)` wants an Identifiable; this wraps the optional id.
  fileprivate var asIdentifiable: Binding<IdentifiedLayout?> {
    Binding<IdentifiedLayout?>(
      get: { wrappedValue.map(IdentifiedLayout.init) }, set: { wrappedValue = $0?.id })
  }
}
