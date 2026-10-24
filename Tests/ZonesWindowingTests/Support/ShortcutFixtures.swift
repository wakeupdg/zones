import CoreGraphics
import Foundation
import ZonesCore
import ZonesLayout

/// Real grid-rounded Zone rectangles from the built-in Templates, never hand-built frames.
enum ShortcutFixtures {
  static let displayA = DisplayKey.uuid("AAAAAAAA-1111-4111-8111-111111111111")
  static let displayB = DisplayKey.uuid("BBBBBBBB-2222-4222-8222-222222222222")
  static let visibleA = CGRect(x: 0, y: 25, width: 1920, height: 1055)
  static let visibleB = CGRect(x: 1920, y: 0, width: 2560, height: 1440)
  static let frameA = CGRect(x: 0, y: 0, width: 1920, height: 1080)
  static let frameB = CGRect(x: 1920, y: 0, width: 2560, height: 1440)

  static func resolved(
    _ template: Template, count: Int, key: DisplayKey = displayA, visible: CGRect = visibleA, scale: Double = 2
  ) -> ResolvedLayout {
    let layout = Templates.generate(template, count: count, insets: Insets(margin: 0, gap: 0))
    return LayoutMath.resolve(layout, key: key, visibleFrame: visible, scale: scale)
  }

  static let key = WindowKey(pid: 4242, elementHash: 7)
}
