# CI runs on pull requests to main and on manual dispatch only; the merge gate is local

Status: accepted (2026-10-24, user decision during Phase 4). Amends ADR-0024 and AC-160 (challenge C11).

GitHub Actions bills macOS runners on a private repository at a high multiplier, and this run pushed dozens of `ticket/**` branches and `integration` merges. The free allowance ran out and every CI job was refused before it started. The user wants the project to stay free of cost.

Decision:
- `.github/workflows/ci.yml` triggers only on `pull_request` to `main` and on `workflow_dispatch`. No `push` trigger.
- The per-ticket regression gate is `scripts/merge-ticket.sh`, which already runs `swift build`, `swift test` and `xcodebuild build` in the ticket worktree before every `--no-ff` merge into `integration`. US-137 ("regressions surface before merge") is met by that gate plus CI on the release pull request.
- The repository becomes public at release time, before the draft pull request to `main`, so CI on that pull request runs at no cost (public repositories get Actions minutes free). Fallback: if the Actions limit blocks a needed CI run earlier, make the repository public early and mark the README as pre-release, heavily buggy and not working yet. A full-history secret scan comes before either switch.

Considered: a self-hosted runner on the development Mac (free, but needs a registration token and an awake machine; kept as the option if the repository must stay private); a local pre-push hook only (no independent check).
