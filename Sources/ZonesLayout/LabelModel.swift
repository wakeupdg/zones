import CoreGraphics
import Foundation
import ZonesCore

public struct ZoneLabel: Hashable, Sendable {
  public var number: Int
  public var text: String
  public var frame: CGRect
  public var outline: RGBA
  public var contentsScale: Double
  public var noChord: Bool
  public init(number: Int, text: String, frame: CGRect, outline: RGBA, contentsScale: Double, noChord: Bool) {
    self.number = number
    self.text = text
    self.frame = frame
    self.outline = outline
    self.contentsScale = contentsScale
    self.noChord = noChord
  }
}

/// One label per Zone, shared by the Overlay and the editor (AC-132).
public enum LabelModel {
  /// `text` is the Zone Number, `frame` the Zone frame, `contentsScale` the Display scale, `noChord` true above 9
  /// (a single digit chord cannot address it). Ordered by number.
  public static func labels(_ r: ResolvedLayout, appearance: Appearance) -> [ZoneLabel] {
    let outline = outlineColor(for: appearance.fill)
    return r.zones.sorted { $0.number < $1.number }.map {
      ZoneLabel(
        number: $0.number, text: String($0.number), frame: $0.frame, outline: outline, contentsScale: r.scale,
        noChord: $0.number > 9)
    }
  }

  /// Black or white (alpha 1), whichever has the higher WCAG contrast ratio with the opaque fill. The fill's own
  /// `a` and the Appearance `opacity` are ignored: the contrast is judged against the opaque fill, so it holds at
  /// any opacity. The worst case (mid gray) is about 4.58.
  static func outlineColor(for fill: RGBA) -> RGBA {
    let l = relativeLuminance(fill)
    let white = (1 + 0.05) / (l + 0.05)
    let black = (l + 0.05) / 0.05
    return white >= black ? RGBA(r: 1, g: 1, b: 1, a: 1) : RGBA(r: 0, g: 0, b: 0, a: 1)
  }

  /// WCAG 2 relative luminance with the sRGB linearization.
  static func relativeLuminance(_ c: RGBA) -> Double {
    func lin(_ v: Double) -> Double {
      let x = min(max(v, 0), 1)
      return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
  }
}
