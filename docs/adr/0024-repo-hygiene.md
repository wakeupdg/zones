# Ticket branches merge into integration with --no-ff; a small CI workflow; private GitHub remote

Each ticket lands via `git merge --no-ff` so `check-state.sh` can prove a done ticket is an ancestor of `integration`. A GitHub Actions workflow runs `swift test` and `xcodebuild build` on a macOS runner. The remote is the private repo `wakeupdg/zones`; only `integration` is pushed during the run, `main` receives the final PR.
