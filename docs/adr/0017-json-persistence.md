# Layouts and assignments are JSON files in Application Support; preferences in UserDefaults

`~/Library/Application Support/Zones/layouts.json` and `assignments.json` hold user data with a top-level `version` field; the export format is the same document. Preferences (modifiers, appearance, shortcuts, exclusions) live in `UserDefaults`. Rejected: everything in UserDefaults (no import/export, hard to diff).
