import Foundation
import ZonesCore

enum TestFixtures {
  static func url(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
  }

  static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }

  static let deskID = LayoutID(rawValue: "37D8832A-2D66-02CA-B9F7-8F30A301B230")
  static let centeredID = LayoutID(rawValue: "9A4B1C2D-0E3F-4A5B-8C6D-7E8F90A1B2C3")
  static let studioKey = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
  static let dormantKey = "6B1F0C3E-52A7-4D98-9E10-3C4D5E6F7A8B"

  static let desk = Layout(
    id: deskID, name: "Desk",
    root: .split(
      axis: .horizontal, ratio: 0.5, first: .leaf,
      second: .split(axis: .vertical, ratio: 0.5, first: .leaf, second: .leaf)),
    surround: Surround(top: 0, left: 0, bottom: 0, right: 0), insets: Insets(margin: 8, gap: 8))

  static let centered = Layout(
    id: centeredID, name: "Centered",
    root: .split(axis: .vertical, ratio: 0.25, first: .leaf, second: .leaf),
    surround: Surround(top: 0.2, left: 0.2, bottom: 0.2, right: 0.2), insets: Insets(margin: 12, gap: 6))

  static let layoutsDocument = ZonesDocument(version: 1, layouts: [desk, centered])

  static let assignmentsDocument = ZonesDocument(
    version: 1,
    assignments: [
      studioKey: Assignment(
        layout: LayoutID(rawValue: "builtin:priorityGrid:3"), displayName: "Studio Display",
        lastVisibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415), lastScale: 2,
        lastSeen: Date(timeIntervalSince1970: 1_792_861_320)),
      dormantKey: Assignment(
        layout: centeredID, displayName: "Dormant Dell",
        lastVisibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055), lastScale: 1,
        lastSeen: Date(timeIntervalSince1970: 1_788_251_400)),
    ])
}
