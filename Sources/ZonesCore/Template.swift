public enum Template: String, Codable, CaseIterable, Sendable {
  case columns = "Columns", rows = "Rows", grid = "Grid", priorityGrid = "Priority Grid", focus = "Focus"

  /// Zone counts offered for each template.
  public var counts: [Int] {
    switch self {
    case .columns, .rows: [2, 3, 4, 5]
    case .grid: [4, 9]
    case .priorityGrid: [3]
    case .focus: [1]
    }
  }
}
