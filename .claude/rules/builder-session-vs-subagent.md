# Ticket work goes to a session, checks go to a subagent

DG, 2026-10-24: "We need to have some sort of logic to this that determines when we would start a builder as a session versus a sub-agent." Agreed rule, used from T58 on.

**Why:**
- T55, T56 and T57 builders (af:builder in isolated agent worktrees) stopped on guards, ~80k tokens each. The Claude Code worktree guard refuses `xcodebuild` and `swift test` there ("cannot be shown not to be git").
- The orchestrator hits its ceiling and goes to `successor` every 1-2 hours. Subagents die with the cleared parent (see successor-collect-background-first.md); sessions survive.
- DG wants to see work in progress in the sidebar, and to steer design work.

**Start a session when ANY is true:**
1. The work ends in a branch (a code ticket with a brief file).
2. The work can outlive the orchestrator's context (more than ~15 min).
3. DG may want to watch or steer it (Figma, icon, any UX choice).
4. It must build or test (`swift test`, `xcodegen`, `xcodebuild`).

**Start a subagent when ALL are true:**
1. It only reads or measures (probe, AC measurement, diff review, screenshot check).
2. It is short (~10 min or less).
3. The orchestrator needs its result for the next step in the same turn.

**How to start a builder session:**
1. `scripts/wt.sh add <id>` (worktree at `../.zones-worktrees/<id>` on `ticket/<id>`).
2. `start_session` with `cwd` = that worktree and `use_worktree: false` (an app worktree may carry the same guard).
3. Brief = the ticket file + the standard limits: no push, no merge, no `merge-ticket.sh`, unsigned build (`ZONES_UNSIGNED=1`), no keychain or `dev-cert.sh`, no `/Applications`, never relaunch or kill the running Zones app.
4. The successor card lists the session links under RE-ARM FIRST as "running, no restart needed".

**Probe status (2026-10-24, session wt-probe in `../.zones-worktrees/T57`, `use_worktree: false`):** `xcodebuild -version`, `swift --version`, `xcodegen --version`, `git status`, `pwd` all ACCEPTED. The same `xcodebuild -version` is REFUSED in an isolated agent worktree. A full `swift test`/`xcodebuild` build was not run in the probe.
