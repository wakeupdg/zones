import SwiftUI
import ZonesCore

/// A rounded key cap for a `Modifier`: glyph plus name. Value-driven, so it redraws when the value changes.
struct KeyCapView: View {
  let modifier: Modifier

  static func glyph(_ modifier: Modifier) -> String {
    switch modifier {
    case .shift: "\u{21E7}"
    case .control: "\u{2303}"
    case .option: "\u{2325}"
    case .command: "\u{2318}"
    }
  }

  var body: some View {
    HStack(spacing: 6) {
      Text(Self.glyph(modifier)).font(.title3)
      Text(modifier.rawValue.capitalized).font(.callout)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(
      RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor))
    )
    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
    .accessibilityElement(children: .combine)
  }
}
