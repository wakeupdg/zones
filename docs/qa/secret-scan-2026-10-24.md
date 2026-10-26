# Secret scan before making the repository public (2026-10-24)

Scope: every blob reachable from every ref (798 commits, 1,429 blobs under 2 MB), plus file names ever committed.

| Check | Result |
|---|---|
| AWS, GitHub, Anthropic, OpenAI, Slack, Google API keys | 0 |
| PEM / OpenSSH private keys | 0 |
| `password|secret|api_key|token = "..."` assignments | 0 |
| Files named *.p12, *.pem, *.key, .env, *keychain*, *credential* | 0 (the only `.p12` is a temp path inside scripts/dev-cert.sh) |
| Blobs over 500 KB | 0 |
| Personal email addresses in file contents | 0 |

Items that become visible when the repository is public (decisions for the owner, not leaks of credentials):
1. Commit metadata: all commits carry the author and committer email of the owner's personal address. GitHub shows it on public commits. Changing it needs a history rewrite and a force-push, which this run's rules forbid.
2. The legacy dev-keychain password `zones-dev` is in history (scripts/dev-cert.sh before T51). It unlocks only the local throwaway keychain that holds the self-signed "Zones Dev" identity. T51 adds `scripts/dev-cert.sh --harden`, which moves the keychain to a random password kept in the login keychain; run it once on the development Mac.
3. Absolute local paths (`/Users/<user>/...`, scratchpad paths) appear in QA notes and ticket briefs. They show the local user name only.
