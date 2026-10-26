# Dev builds are signed with a stable self-signed "Zones Dev" identity

Ad-hoc signing changes the code hash on every rebuild, so macOS drops the Accessibility grant each time (tested in research: event-taps-tcc.md). A self-signed code-signing certificate named "Zones Dev" in the login keychain gives a stable designated requirement; `scripts/dev-cert.sh` creates it on demand. Release builds use `ZONES_SIGN_IDENTITY` when set, else ad-hoc (settled).

## Amendment 2026-10-24 (LOCKED-SPEC AC-014)

The release script is `scripts/release.sh`. Its `--dry-run` flag performs every step except signing, notarization and DMG creation and prints the signing decision; with `ZONES_SIGN_IDENTITY` unset it prints exactly one stderr line containing "ad-hoc" and exits 0, so the fallback is loud and testable without a certificate.
