/// The About pane's five items (AC-029), filled from `BundleInfo`.
public struct AboutModel: Hashable, Sendable {
  public var version: String
  public var build: String
  public var signingIdentity: String
  public var license: String
  /// Exactly one line, and the only text that mentions "FancyZones".
  public var attribution: String

  public init(bundle: BundleInfo) {
    version = bundle.version
    build = bundle.build
    signingIdentity = bundle.signingIdentity
    license = "MIT"
    attribution = "inspired by FancyZones"
  }
}
