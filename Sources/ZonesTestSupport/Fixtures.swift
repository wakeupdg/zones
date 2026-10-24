import CoreGraphics
import ZonesCore

public enum Fixtures {
  /// Primary 1x (0,0,1920,1080); a 2x display to its left (-1440,0,1440,900);
  /// a 1x portrait display above it with a negative origin (-600,1080,1080,1920).
  public static let threeDisplays: TopologySnapshot = {
    let primaryFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let primary = DisplaySnapshot(
      key: .uuid("11111111-1111-4111-8111-111111111111"), frame: primaryFrame,
      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),  // 25 pt menu bar at the top
      scale: 1, isMain: true, mirrorOf: nil, name: "Primary 1x",
      resolution: CGSize(width: 1920, height: 1080))
    let retinaFrame = CGRect(x: -1440, y: 0, width: 1440, height: 900)
    let retina = DisplaySnapshot(
      key: .uuid("22222222-2222-4222-8222-222222222222"), frame: retinaFrame, visibleFrame: retinaFrame,
      scale: 2, isMain: false, mirrorOf: nil, name: "Left 2x",
      resolution: CGSize(width: 2880, height: 1800))
    let portraitFrame = CGRect(x: -600, y: 1080, width: 1080, height: 1920)
    let portrait = DisplaySnapshot(
      key: .uuid("33333333-3333-4333-8333-333333333333"), frame: portraitFrame,
      visibleFrame: portraitFrame, scale: 1, isMain: false, mirrorOf: nil, name: "Portrait 1x",
      resolution: CGSize(width: 1080, height: 1920))
    return TopologySnapshot(
      displays: [primary, retina, portrait], separateSpaces: true, primaryFrame: primaryFrame)
  }()
}
