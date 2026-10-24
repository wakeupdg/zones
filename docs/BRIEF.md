# Zones — product brief (locked inputs for Phase 1)

Name: Zones. Bundle id: com.dganesh.zones. License: MIT. One "inspired by FancyZones" line only.
Target: macOS 14+, universal binary. Stack and decisions: see docs/adr/ (25 ADRs) and CONTEXT.md (glossary).

## MVP feature set
- Menu-bar app (no Dock icon).
- Onboarding for the Accessibility permission; re-onboard when revoked.
- Templates: Columns, Rows, Grid, Priority Grid, Focus.
- Custom layout editor: split, merge, resize, margins and gaps.
- Layouts per display (per Space only if the spike in ADR-0013 passes).
- Hold the activation modifier (default Shift) while dragging: the overlay shows zones; drop snaps.
- Span several zones with the span modifier (default Control).
- Shortcuts: send focused window to zone N; cycle zones; restore original frame; open editor; open settings.
- Restore original frame.
- Per-app exclusions.
- Zone appearance: color, opacity, padding (margin and gap).
- Launch at login.
- Settings window: General, Layouts, Shortcuts, Appearance, Exclusions, About.
- Import and export layouts as JSON.

## Out of scope for v1
Auto-update, cloud sync, Windows-parity edge cases, iCloud, localization beyond English, re-snap after display changes, tiling (evicting other windows), App Store distribution.

## Distribution
`scripts/release.sh` builds a DMG under dist/. Developer ID signing when ZONES_SIGN_IDENTITY is set, else ad-hoc. Homebrew cask under Casks/.

## Research (read the "Implications for Zones" section of each)
docs/research/ax-window-moves.md, cgwindowlist-ownership.md, spaces-and-displays.md, event-taps-tcc.md, login-items.md, overlay-panels.md
