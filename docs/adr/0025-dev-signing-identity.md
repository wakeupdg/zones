# Dev builds are signed with a stable self-signed "Zones Dev" identity

Ad-hoc signing changes the code hash on every rebuild, so macOS drops the Accessibility grant each time (tested in research: event-taps-tcc.md). A self-signed code-signing certificate named "Zones Dev" in the login keychain gives a stable designated requirement; `scripts/dev-cert.sh` creates it on demand. Release builds use `ZONES_SIGN_IDENTITY` when set, else ad-hoc (settled).
