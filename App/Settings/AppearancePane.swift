import AppKit
import Observation
import SwiftUI
import ZonesCore
import ZonesLayout
import ZonesWindowing

/// Appearance edits. Every change goes through the `PreferencesController` (so the next Drag Session sees it),
/// and a change to Margin or Gap also regenerates the built-in Layouts in the Layouts list (AC-117).
@MainActor @Observable
final class AppearanceModel {
  @ObservationIgnored private let preferences: PreferencesController
  @ObservationIgnored private let layouts: ImportExportController

  init(preferences: PreferencesController, layouts: ImportExportController) {
    self.preferences = preferences
    self.layouts = layouts
    layouts.setDefaultInsets(preferences.preferences.appearance.defaultInsets)
  }

  var appearance: Appearance { preferences.preferences.appearance }
  var enhancedUI: EnhancedUIPolicy { preferences.preferences.enhancedUI }

  /// The Layouts that follow the default Margin and Gap right now.
  var sample: AppearanceSample {
    AppearanceSample(defaults: appearance.defaultInsets, store: layouts.flow.store)
  }

  func setOpacity(_ value: Double) { preferences.update { $0.appearance.opacity = min(max(value, 0), 1) } }

  func setFill(_ fill: RGBA) { preferences.update { $0.appearance.fill = fill } }

  func setMargin(_ value: Double) {
    var insets = appearance.defaultInsets
    insets.margin = max(value, 0)
    setInsets(insets)
  }

  func setGap(_ value: Double) {
    var insets = appearance.defaultInsets
    insets.gap = max(value, 0)
    setInsets(insets)
  }

  func setEnhancedUI(_ policy: EnhancedUIPolicy) { preferences.update { $0.enhancedUI = policy } }

  private func setInsets(_ insets: Insets) {
    preferences.update { $0.appearance.defaultInsets = insets }
    layouts.setDefaultInsets(insets)
  }
}

/// Fill color and opacity with a live sample, the default Margin and Gap, and the Enhanced UI policy.
struct AppearancePane: View {
  let model: AppearanceModel

  var body: some View {
    let appearance = model.appearance
    let sample = model.sample
    Form {
      Section("Zone highlight") {
        ColorPicker(
          "Fill color",
          selection: Binding(
            get: { Self.color(appearance.fill) }, set: { model.setFill(Self.rgba($0, fallback: appearance.fill)) }),
          supportsOpacity: false)
        LabeledContent("Opacity") {
          HStack {
            Slider(value: Binding(get: { appearance.opacity }, set: { model.setOpacity($0) }), in: 0...1)
              .frame(width: 180)
            Text(appearance.opacity, format: .percent.precision(.fractionLength(0))).monospacedDigit()
              .frame(width: 44, alignment: .trailing)
          }
        }
        sampleView(appearance: appearance, sample: sample)
      }
      Section("Default Margin and Gap") {
        sliderRow(
          "Margin", value: Binding(get: { appearance.defaultInsets.margin }, set: { model.setMargin($0) }))
        sliderRow("Gap", value: Binding(get: { appearance.defaultInsets.gap }, set: { model.setGap($0) }))
        Text("Built-in Layouts always use these. Custom Layouts keep their own unless they match.")
          .font(.callout).foregroundStyle(.secondary)
      }
      Section("Apps that need Enhanced UI off") {
        Picker("Enhanced UI", selection: Binding(get: { model.enhancedUI }, set: { model.setEnhancedUI($0) })) {
          Text("Turn off while snapping").tag(EnhancedUIPolicy.toggle)
          Text("Leave as it is").tag(EnhancedUIPolicy.leave)
        }
      }
    }
    .formStyle(.grouped)
  }

  private func sampleView(appearance: Appearance, sample: AppearanceSample) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      let insets = appearance.defaultInsets
      ZStack {
        RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor))
        HStack(spacing: min(insets.gap, 24)) {
          ForEach(0..<2, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 4)
              .fill(Self.color(appearance.fill).opacity(appearance.opacity))
              .overlay(RoundedRectangle(cornerRadius: 4).stroke(Self.color(appearance.fill)))
          }
        }
        .padding(min(insets.margin, 40))
      }
      .frame(height: 70)
      .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
      .accessibilityLabel("Sample of two Zones")
      Text("Layouts following these: \(sample.summary)").font(.callout).foregroundStyle(.secondary)
    }
  }

  private func sliderRow(_ title: String, value: Binding<Double>) -> some View {
    LabeledContent(title) {
      HStack {
        Slider(value: value, in: 0...40, step: 1).frame(width: 180)
        Text("\(Int(value.wrappedValue)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
      }
    }
  }

  static func color(_ fill: RGBA) -> Color { Color(.sRGB, red: fill.r, green: fill.g, blue: fill.b, opacity: 1) }

  static func rgba(_ color: Color, fallback: RGBA) -> RGBA {
    guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return fallback }
    return RGBA(
      r: Double(converted.redComponent), g: Double(converted.greenComponent), b: Double(converted.blueComponent),
      a: fallback.a)
  }
}
