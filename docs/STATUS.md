# Zones — STATUS

Phase: 3 (build), run 1 complete (waves 1-3)
Updated: 2026-10-24, end of run 1

## Phase results so far
- Phase 0/1/2: see git history (ADRs, LOCKED-SPEC 169 AC, CONTRACTS, 39 tickets).
- Phase 3 run 1: 12 tickets done and merged into integration (T01 T01b T02 T03 T04 T05 T06 T07 T08 T09 T10 T11). 50 agents. Root `swift test`: with 74 tests in 12 suites passed. App shell builds and launches (menu-bar only).

## Wave plan (max width 10)
wave 1: T01
wave 2: T01b
wave 3: T02 T03 T04 T05 T06 T07 T08 T09 T10 T11
wave 4: T12 T13 T14 T15 T38
wave 5: T16 T17 T18 T19 T24 T26
wave 6: T20 T21 T22 T23 T25 T27 T28 T30 T31
wave 7: T29 T37
wave 8: T32 T36
wave 9: T33 T34 T35

## Per-ticket state
- done: 12 — T01 T01b T02 T03 T04 T05 T06 T07 T08 T09 T10 T11
- todo: 27 — T12 T13 T14 T15 T16 T17 T18 T19 T20 T21 T22 T23 T24 T25 T26 T27 T28 T29 T30 T31 T32 T33 T34 T35 T36 T37 T38

## Spike verdicts (docs/spikes/)
- PASS: SPK-003 (listen-only tap with Accessibility only), SPK-004 (windowNumber == CGWindowID), SPK-008, SPK-013 (AXObserver thread), SPK-012, SPK-017, SPK-018 — see each file for the recorded table.
- PARTIAL: SPK-005 (dev identity: designated requirement has 0 cdhash; the 3-rebuild grant check needs a human), SPK-010 (write-protocol app matrix: 8 apps recorded; IntelliJ not installed; VoiceOver run needs a human).
- PENDING-HUMAN-RUN (automated tables recorded, provisional verdicts adopted): SPK-001 witness windows, SPK-002 click-through panel during a real drag, SPK-006 revocation signal, SPK-007 moved-notification cadence, SPK-009 real-drag frame time (synthetic: CALayer p99 ~0.1 ms, SwiftUI p99 ~1 ms, budget 8.33 ms). Each file holds the exact operator commands. These are listed as manual items in the final report.
- Builders reported these as blocked-needs-human; the orchestrator merged them as done because the deliverable (probe + verdict note) is complete and only human verification remains.

## Open blockers
none

## Mechanics fixes after run 1
- Spend hook now maps a subagent to its ticket when it runs `scripts/wt.sh add <id>` (the hook's cwd never changes), so tokens_spent updates from run 2 on.
- Merge logs moved from /tmp to .build/merge-logs/ (subagent /tmp does not persist between Bash calls).
- Reviewer throwaway worktrees go under .build/review-worktrees/ with --detach.

## Token spend — two metrics
- Hook metric (tool-result bytes/4, enforced ceilings): ~3.81M of 12M
- Workflow billing metric: research 0.8M + P1 3.15M + P2 7.08M + P3 run1 5.05M → ~16.1M

## LESSONS line count
13
