import SwiftUI
import ZonesWindowing

/// Page 1 (why Accessibility, Open System Settings, status, conditional Quit and Reopen) and the Back/Next
/// paging to the cheat sheet. Back is disabled on page 1 and Next on the last page.
struct OnboardingView: View {
  let model: OnboardingModel

  var body: some View {
    VStack(spacing: 0) {
      Group {
        switch model.page {
        case .accessibility: AccessibilityPage(model: model)
        case .cheatSheet: CheatSheetView(preferences: model.preferences)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(24)
      Divider()
      HStack {
        Button("Back") { model.page = .accessibility }
          .disabled(!model.canGoBack)
        Spacer()
        Button("Next") { model.page = .cheatSheet }
          .disabled(!model.canGoNext)
      }
      .padding(12)
    }
    .frame(width: 480, height: 360)
  }
}

private struct AccessibilityPage: View {
  let model: OnboardingModel

  var body: some View {
    let state = model.viewState
    VStack(alignment: .leading, spacing: 14) {
      Text("Zones needs Accessibility access").font(.title2.bold())
      Text(
        "Zones moves and resizes windows in other apps. macOS only allows that after you turn on Zones in \(model.accessibilityPath)."
      )
      .fixedSize(horizontal: false, vertical: true)
      Label(state.statusLine, systemImage: "info.circle").foregroundStyle(.secondary)
      if let explanation = state.relaunchExplanation {
        Text(explanation).fixedSize(horizontal: false, vertical: true)
      }
      // T56: a stale Accessibility entry (ON in the list, keyed to an older signature) after 10 s of waiting.
      if let help = state.staleEntryHelp {
        Text(help).fixedSize(horizontal: false, vertical: true).accessibilityLabel(help)
      }
      HStack {
        if state.showOpenSettings {
          Button("Open System Settings", action: model.openSettings).keyboardShortcut(.defaultAction)
        }
        if state.showQuitAndReopen {
          Button("Quit and Reopen", action: model.quitAndReopen)
        }
      }
    }
  }
}
