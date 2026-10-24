# Ticket branches merge into integration with --no-ff; a small CI workflow; private GitHub remote

Each ticket lands via `git merge --no-ff` so `check-state.sh` can prove a done ticket is an ancestor of `integration`. A GitHub Actions workflow runs `swift test` and `xcodebuild build` on a macOS runner. The remote is the private repo `wakeupdg/zones`; only `integration` is pushed during the run, `main` receives the final PR.


Amendment (2026-10-24, ADR-0026): CI no longer runs on every push. It runs on pull requests to `main` and on manual dispatch; the local merge gate in `scripts/merge-ticket.sh` covers every ticket merge. The repository becomes public at release time.
