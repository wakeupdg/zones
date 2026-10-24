# LESSONS (curated; 40 lines max; one line per tool quirk or repeated mistake)
<!-- Add one line per lesson. Delete a line when a script or hook now enforces it. -->
- Run builds and tests through `scripts/q.sh`; the PreToolUse hook rewrites bare `swift build|test` and `xcodebuild` (verified live; look for `[q.sh] exit=`).
- Spend hook: a subagent in the main checkout logs under `docs/tickets/_subagents/`; only worktree agents on `ticket/<id>` update `tokens_spent`.
- Read files by line range (`sed -n 'a,bp'`); never cat a whole directory or a generated .xcodeproj.
- macOS has no `flock`; use a `mkdir` lock for shared files such as `graph.json`.
- `swift test` cannot drive AppKit UI; keep window/overlay code behind protocols so logic packages test headless.
- Ticket agents never edit `docs/tickets/graph.json`; only the orchestrator does (the hook updates `tokens_spent`).
- Keep `ticket/<id>` branches after merge; `check-state.sh` uses them to prove a `done` ticket is in `integration`.
- Reviewing a ticket branch that is already checked out in `.zones-worktrees/<id>`: `git worktree add <path> ticket/<id>` fails ("already used by worktree"); use `git worktree add --detach <path> ticket/<id>` and `git worktree remove --force` afterwards.
- Sandboxed Bash gives each call its own `/tmp`: a review worktree added at `/tmp/...` is gone on the next call (and later `cd` silently falls back to the main checkout, so `q.sh` then tests the wrong tree). Put throwaway worktrees under the session scratchpad dir instead.
- swift-testing `--filter Suite.name` runs 0 tests (exit 0, only a warning) when the `@Test` is a free function; an AC verify command that names `GeneratorTests.x` needs the test inside `@Suite struct GeneratorTests`.
- Review worktrees: `git worktree add /tmp/x ticket/TNN` fails with "already used by worktree" because the implementer's .zones-worktrees/TNN holds the branch; use `git worktree add --detach /tmp/x ticket/TNN` (reviewer, T11, 2026-10-24).
- Several reviewers of one ticket run at once: a throwaway worktree named only by ticket (`.../zones-review-T05`) collides with the sibling reviewer's (`git worktree add` fails or you build/remove their tree); suffix the path with your lens (`zones-review-T05-cc`).
- JSON goldens under Tests/<Target>/Fixtures/ load fine via `#filePath` but SwiftPM prints "found N file(s) which are unhandled" on every build; it is a package-manifest warning, not a swiftc one, so `treatAllWarnings(as: .error)` does not fail the build (T10 review, 2026-10-24).
