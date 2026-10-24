#!/usr/bin/env bash
# merge-ticket.sh — deterministic merge of ticket/<id> into integration.
# Steps: check-state; rebase the ticket worktree onto integration; swift build; swift test;
#        xcodebuild build (if project.yml exists); merge --no-ff into integration (main checkout);
#        graph-set done; remove the worktree; push integration.
# Exit 0 = merged. Exit 10 = rebase conflict. 11 = build failed. 12 = tests failed. 13 = xcodebuild failed.
# 14 = merge failed. 15 = check-state mismatch. Output is kept short; full logs in .build/merge-logs/<id>.*.log
set -uo pipefail
id="$1"
common="$(git rev-parse --git-common-dir)"; case "$common" in /*) ;; *) common="$PWD/$common";; esac
main="$(cd "$(dirname "$common")" && pwd)"
q="$main/scripts/q.sh"
mkdir -p "$main/.build/merge-logs"
L="$main/.build/merge-logs/$id"
wt="$("$main/scripts/wt.sh" add "$id")"
cd "$main"
[ "$(git rev-parse --abbrev-ref HEAD)" = "integration" ] || { echo "main checkout is not on integration"; exit 15; }
"$main/scripts/graph-set.sh" "$id" merging >/dev/null
if ! "$main/scripts/check-state.sh" >"$L".state.log 2>&1; then
  grep -v "^MISMATCH: $id " "$L".state.log | grep -q MISMATCH && { echo "check-state mismatch (not about $id):"; grep MISMATCH "$L".state.log | head -5; exit 15; }
fi
cd "$wt"
git add -A >/dev/null 2>&1; git diff --cached --quiet || git commit -q -m "wip: uncommitted work at merge time" >/dev/null 2>&1
if ! git rebase -q integration >"$L".rebase.log 2>&1; then
  git rebase --abort 2>/dev/null; echo "REBASE CONFLICT:"; tail -15 "$L".rebase.log; exit 10
fi
Q_LINES=25 Q_LOG="$L".build.log "$q" swift build || { echo "BUILD FAILED"; exit 11; }
Q_LINES=25 Q_LOG="$L".test.log "$q" swift test || { echo "TESTS FAILED"; exit 12; }
if [ -f project.yml ]; then
  Q_LINES=10 "$q" xcodegen generate >/dev/null || { echo "XCODEGEN FAILED"; exit 13; }
  Q_LINES=25 Q_LOG="$L".xcode.log "$q" xcodebuild -quiet -project Zones.xcodeproj -scheme Zones -configuration Debug -derivedDataPath .build/DerivedData CODE_SIGN_IDENTITY="Zones Dev" build || { echo "XCODEBUILD FAILED"; exit 13; }
fi
cd "$main"
if ! git merge --no-ff -q -m "merge: $id into integration

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" "ticket/$id" >"$L".merge.log 2>&1; then
  git merge --abort 2>/dev/null; echo "MERGE FAILED:"; tail -10 "$L".merge.log; exit 14
fi
"$main/scripts/wt.sh" remove "$id" >/dev/null
"$main/scripts/graph-set.sh" "$id" done "merged $(git rev-parse --short HEAD)" >/dev/null
git push -q origin integration 2>/dev/null || echo "(push failed; continuing)"
echo "MERGED $id -> integration $(git rev-parse --short HEAD)"
exit 0
