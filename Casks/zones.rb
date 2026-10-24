cask "zones" do
  version "0.1.0"
  # Placeholder: scripts/release.sh prints the real sha256 line for the DMG it builds.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/wakeupdg/zones/releases/download/v#{version}/Zones-#{version}.dmg"
  name "Zones"
  desc "Menu-bar window snapping into zone layouts"
  homepage "https://github.com/wakeupdg/zones"

  depends_on macos: ">= :sonoma"

  app "Zones.app"

  zap trash: [
    "~/Library/Application Support/Zones",
    "~/Library/Preferences/com.dganesh.zones.plist",
  ]
end
