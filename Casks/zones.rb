cask "zones" do
  version "0.1.0"
  # sha256 of dist/Zones-0.1.0.dmg (ad-hoc signed) built by scripts/release.sh on 2026-10-24.
  sha256 "fec98598883d4f8388c994ed710fd2e079c3e5b0409f5e18360aa6343daeeadc"

  url "https://github.com/wakeupdg/zones/releases/download/v#{version}/Zones-#{version}.dmg"
  name "Zones"
  desc "Menu-bar window snapping into zone layouts"
  homepage "https://github.com/wakeupdg/zones"

  depends_on macos: :sonoma

  app "Zones.app"

  zap trash: [
    "~/Library/Application Support/Zones",
    "~/Library/Preferences/com.dganesh.zones.plist",
  ]
end
