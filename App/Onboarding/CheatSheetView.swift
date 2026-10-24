import SwiftUI
import ZonesCore

/// The last onboarding page: the three gestures. Key caps are value-driven, so they redraw when the
/// Activation or Span Modifier changes.
struct CheatSheetView: View {
  let preferences: Preferences

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("How to use Zones").font(.title2.bold())
      row("Hold to see Zones while dragging a window") {
        KeyCapView(modifier: preferences.activationModifier)
      }
      row("Add to span several zones") {
        KeyCapView(modifier: preferences.activationModifier)
        Text("+")
        KeyCapView(modifier: preferences.spanModifier)
      }
      row("Send the front window to zone N") {
        KeyCapView(modifier: .control)
        Text("+")
        KeyCapView(modifier: .option)
        Text("+")
        Text("N").font(.callout.monospaced())
      }
    }
  }

  private func row<Caps: View>(_ title: String, @ViewBuilder caps: () -> Caps) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
      HStack(spacing: 6) { caps() }
    }
  }
}
