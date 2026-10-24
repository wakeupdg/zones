import SwiftUI
import ZonesWindowing

/// Page 1 (why Accessibility, Open System Settings, status, conditional Quit and Reopen) and the Back/Next
/// paging to the cheat sheet. Next and Back are always enabled.
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
          .disabled(false)
          .opacity(model.page == .accessibility ? 0.4 : 1)
        Spacer()
        Button("Next") { model.page = .cheatSheet }
          .opacity(model.page == .cheatSheet ? 0.4 : 1)
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
        "Zones moves and resizes windows in other apps. macOS only allows that after you turn on Zones in Privacy & Security > Accessibility."
      )
      .fixedSize(horizontal: false, vertical: true)
      Label(state.statusLine, systemImage: "info.circle").foregroundStyle(.secondary)
      if let explanation = state.relaunchExplanation {
        Text(explanation).fixedSize(horizontal: false, vertical: true)
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
