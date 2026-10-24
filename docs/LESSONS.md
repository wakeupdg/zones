# LESSONS (curated; 40 lines max; one line per tool quirk or repeated mistake)
<!-- Add one line per lesson. Delete a line when a script or hook now enforces it. -->
- Run builds and tests through `scripts/q.sh`; the PreToolUse hook rewrites bare `swift build|test` and `xcodebuild` (verified live; look for `[q.sh] exit=`).
- Spend hook: a subagent in the main checkout logs under `docs/tickets/_subagents/`; only worktree agents on `ticket/<id>` update `tokens_spent`.
- Read files by line range (`sed -n 'a,bp'`); never cat a whole directory or a generated .xcodeproj.
- macOS has no `flock`; use a `mkdir` lock for shared files such as `graph.json`.
- `swift test` cannot drive AppKit UI; keep window/overlay code behind protocols so logic packages test headless.
- Ticket agents never edit `docs/tickets/graph.json`; only the orchestrator does (the hook updates `tokens_spent`).
- Keep `ticket/<id>` branches after merge; `check-state.sh` uses them to prove a `done` ticket is in `integration`.
