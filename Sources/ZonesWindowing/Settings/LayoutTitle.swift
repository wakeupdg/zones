import ZonesCore

extension Layout {
  /// The name the Layouts pane and pickers show. Built-ins share Template names across Zone counts, so they
  /// carry the count; custom Layouts show their own name.
  public var pickerTitle: String {
    guard let builtIn else { return name }
    return builtIn.count == 1 ? "\(name) (1 zone)" : "\(name) (\(builtIn.count) zones)"
  }
}
