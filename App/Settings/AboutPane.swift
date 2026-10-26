import SwiftUI
import ZonesWindowing

/// The five `AboutModel` items as labelled rows (AC-029, AC-030). System colors only.
struct AboutPane: View {
  let model: AboutModel

  var body: some View {
    Form {
      LabeledContent("Version", value: model.version)
      LabeledContent("Build", value: model.build)
      LabeledContent("Signing identity", value: model.signingIdentity)
      LabeledContent("License", value: model.license)
      Text(model.attribution).foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
  }
}
