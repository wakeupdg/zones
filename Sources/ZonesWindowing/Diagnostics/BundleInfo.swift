import Foundation
import Security

public struct BundleInfo: Hashable, Sendable {
  public var version: String
  public var build: String
  /// Common name of the leaf signing certificate, or "ad-hoc".
  public var signingIdentity: String
  public var macOS: String

  public init(version: String, build: String, signingIdentity: String, macOS: String) {
    self.version = version
    self.build = build
    self.signingIdentity = signingIdentity
    self.macOS = macOS
  }

  public static let adHoc = "ad-hoc"

  /// Pure and testable. No certificate or an empty name gives "ad-hoc"; a missing version or build gives "unknown".
  public static func make(
    infoDictionary: [String: Any]?, signingCommonName: String?, osVersion: OperatingSystemVersion
  ) -> BundleInfo {
    func string(_ key: String) -> String {
      guard let value = infoDictionary?[key] as? String, !value.isEmpty else { return "unknown" }
      return value
    }
    let name = signingCommonName ?? ""
    return BundleInfo(
      version: string("CFBundleShortVersionString"), build: string("CFBundleVersion"),
      signingIdentity: name.isEmpty ? adHoc : name,
      macOS: "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")
  }

  /// Reads the running bundle, the OS version and the signature of this process.
  public static func current() -> BundleInfo {
    make(
      infoDictionary: Bundle.main.infoDictionary, signingCommonName: runningSigningCommonName(),
      osVersion: ProcessInfo.processInfo.operatingSystemVersion)
  }

  private static func runningSigningCommonName() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
    var info: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
      let dict = info as? [String: Any],
      let certificates = dict[kSecCodeInfoCertificates as String] as? [SecCertificate],
      let leaf = certificates.first
    else { return nil }
    var name: CFString?
    guard SecCertificateCopyCommonName(leaf, &name) == errSecSuccess else { return nil }
    return name as String?
  }
}
