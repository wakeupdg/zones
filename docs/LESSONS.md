# LESSONS (curated; 40 lines max; one line per tool quirk or repeated mistake)
<!-- Add one line per lesson. Delete a line when a script or hook now enforces it. -->
- Run builds and tests through `scripts/q.sh`; the PreToolUse hook rewrites bare `swift build|test` and `xcodebuild` (verified live; look for `[q.sh] exit=`).
- Spend hook: a subagent in the main checkout logs under `docs/tickets/_subagents/`; only worktree agents on `ticket/<id>` update `tokens_spent`.
- Read files by line range (`sed -n 'a,bp'`); never cat a whole directory or a generated .xcodeproj.
- macOS has no `flock`; use a `mkdir` lock for shared files such as `graph.json`.
- `swift test` cannot drive AppKit UI; keep window/overlay code behind protocols so logic packages test headless.
- Ticket agents never edit `docs/tickets/graph.json`; only the orchestrator does (the hook updates `tokens_spent`).
- Keep `ticket/<id>` branches after merge; `check-state.sh` uses them to prove a `done` ticket is in `integration`.
- swift-testing `--filter Suite.name` runs 0 tests (exit 0, only a warning) when the `@Test` is a free function; an AC verify command that names `GeneratorTests.x` needs the test inside `@Suite struct GeneratorTests`.
- JSON goldens under Tests/<Target>/Fixtures/ load fine via `#filePath` but SwiftPM prints "found N file(s) which are unhandled" on every build; it is a package-manifest warning, not a swiftc one, so `treatAllWarnings(as: .error)` does not fail the build (T10 review, 2026-10-24).
- Review worktrees: the builder holds `ticket/<id>` in `.zones-worktrees/<id>`, so add a throwaway with `git worktree add --detach .build/review-worktrees/<id>-<lens> ticket/<id>` (unique per reviewer, never under /tmp, which does not persist between a subagent's Bash calls); `git worktree remove --force` it afterwards.
- Merge logs live in `.build/merge-logs/<id>.*.log`; `scripts/merge-ticket.sh` exit codes: 10 rebase, 11 build, 12 tests, 13 xcodebuild, 14 merge, 15 check-state.
