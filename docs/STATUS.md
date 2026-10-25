# Zones — STATUS

Phase: 5 (release) COMPLETE — 57 of 57 tickets done, 0 blocked (T55, T56 fix tickets from the human run); draft PR integration -> main and draft release v0.1.0
Updated: 2026-10-24, end of Phase 5

## Result
- Tickets: 55 done, 0 todo, 0 blocked (T01..T54, T01b included).
- Acceptance: 169 ACs. Auto 139: 139 pass, 0 fail. Manual 30: 4 pass in a human run on 2026-10-24 (AC-004, AC-010, AC-057, AC-066); AC-009 FAIL (revocation not detected, heartbeat off per SPK-006 provisional default); AC-005 blocked by AC-009; 24 need a human run (list below). Source: docs/qa/acceptance-matrix.md.
- Root `swift test` at the end of Phase 5: 337 tests in 66 suites green.
- Release artifact: dist/Zones-0.1.0.dmg, 2,825,607 bytes, sha256 fec98598883d4f8388c994ed710fd2e079c3e5b0409f5e18360aa6343daeeadc. Ad-hoc signed: `hdiutil verify` VALID, `codesign` ok, `spctl` rejects (no Developer ID).
- Homebrew cask: Casks/zones.rb points at the v0.1.0 release asset; `depends_on macos: :sonoma`.

## Phase results
- Phase 0/1/2: research, ADRs, LOCKED-SPEC (169 AC), CONTRACTS, 39 tickets. See git history.
- Phase 3 (build): 4 runs, 40 tickets merged (T01..T39). T37 found a real reducer bug; fix ticket T39.
- Phase 4 (QA): 2 rounds.
  - Round 1: 21 raw findings, 13 confirmed, 8 dropped; fix tickets T40..T46 merged.
  - Round 2: 11 raw findings, 10 confirmed, 1 dropped; fix tickets T47..T51 merged.
  - QA stopped after round 2 by the 10M rule (hook metric ~9.37M at that time). No round 3.
  - T52: CI triggers (ADR-0026). CI runs on a PR to main and on a manual start only, at zero cost.
- Phase 5 (release): T53 docs (README, CHANGELOG, docs/ARCHITECTURE.md) and T54 media (demo GIF, DMG, cask) merged.
  - Test fix at merge: `InputSourceTests.callbackBoxYieldsSignalsAndEvents` compared event flags with `[]`. macOS 27 sets `maskNonCoalesced` on a new `CGEvent`, so the test now compares the flags before and after the callback.

## Spike verdicts (docs/spikes/)
- PASS: SPK-003, SPK-004, SPK-008, SPK-012, SPK-013, SPK-015, SPK-017, SPK-018.
- PARTIAL: SPK-005 (3-rebuild grant check needs a human), SPK-010 (VoiceOver run needs a human).
- PENDING-HUMAN-RUN: SPK-001, SPK-002, SPK-006, SPK-007, SPK-009. Each file holds the operator commands.

## Manual ACs (need a human run)
Passed in the human run on 2026-10-24 (macOS 27.0.1): AC-004, AC-010, AC-057, AC-066. Checklist: docs/qa/priority-manual-acs.md.

Failed: AC-009. Blocked by AC-009: AC-005.

Still open (24):
AC-020, AC-023, AC-025, AC-028, AC-030, AC-040, AC-044, AC-046, AC-061, AC-064, AC-070, AC-075, AC-078, AC-085, AC-096, AC-106, AC-107, AC-119, AC-126, AC-139, AC-141, AC-144, AC-157, AC-168.

## Open items
The list of record is "Known issues" in CHANGELOG.md (0.1.0). In short:
- Live drag, Snap and overlay behavior is not verified on real hardware.
- AC-009 FAIL in the human run; fixed by T55 (trust probe in the 5 s health tick, C12; SPK-006 verdict from trial 1). Needs a human re-run on a signed build, then AC-005.
- T56 (merged): the onboarding window shows a stale-entry help line after 10 s (C13). Not yet seen on screen.
- Dev signing: the zones-dev keychain rejects its stored password since about 7:49 PM PT on 2026-10-24. T55 and T56 merged with `ZONES_UNSIGNED=1` (unsigned xcodebuild gate). Recreate the keychain with scripts/dev-cert.sh, then re-grant Accessibility.
- The 24 open manual ACs above.
- `scripts/dev-cert.sh` recovery path fails when the dev keychain exists but holds no identity (T51 review).
- Copy Diagnostics has no menu item or button yet.
- Reviewer non-blockers from T12, T13, T14, T17, T23, T28/T30, T33, T39 (details in CHANGELOG.md).

## Open blockers
- None. GitHub billing no longer blocks CI: T52 limits CI to a PR to main and a manual start.

## Token spend — two metrics
- Hook metric (tool-result bytes/4, enforced ceilings): ~9.7M of 12M at the end of Phase 5 (ledger figure; the per-ticket spend.log sum is 8.45M because some workflow agents log elsewhere).
- Workflow billing metric: ~35.1M at the end of Phase 3. The ledger does not record the Phase 4 and Phase 5 workflow billing figures.

## LESSONS line count
38
