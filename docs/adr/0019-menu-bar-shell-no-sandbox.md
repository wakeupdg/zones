# Menu-bar-only app, hardened runtime, no App Sandbox

`LSUIElement` is true (no Dock icon). The menu shows a layout picker for the display under the cursor, Edit Layouts, Settings, Quit. Settings has General, Layouts, Shortcuts, Appearance, Exclusions, About. The Accessibility API is unavailable to sandboxed apps, so there is no sandbox; hardened runtime stays on for notarization. Distribution is DMG and Homebrew cask, never the App Store.
