# T31 ledger
- SPK verdicts: SPK-002 and SPK-009 exist and are PENDING-HUMAN-RUN; SPK-009 records "T31 rendering: CALayer", so pure CALayer, no NSHostingView. `canJoinAllApplications` kept (SPK-002 does not drop it).
- Tooling: AppTests could not load under the hardened-runtime host (Team ID mismatch with the self-signed "Zones Dev" identity), so project.yml sets ENABLE_HARDENED_RUNTIME NO for the Zones target in Debug only (Release unchanged). AppTests also gets the three package products.
- Quirk: `isFloatingPanel = true` resets `level` to .floating, so `level = .screenSaver` must be set after it. `hasKeyAppearance`/`hasActiveAppearance` are not overridable on NSWindow in this SDK, so not overridden.
- slice 1: OverlayPanelTests.configuration green — ZoneOverlayPanel with the ADR-0023 recipe (orderFrontCount, fit(to:)).
