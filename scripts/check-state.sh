#!/usr/bin/env bash
# check-state.sh — compare docs/tickets/graph.json states with git truth.
# Checks: branches ticket/<id>, open worktrees, and whether done tickets are merged into integration.
# Prints every mismatch. Exit 1 on any mismatch, 0 when clean.
set -u
root="$(git rev-parse --show-toplevel)" || exit 2
cd "$root"
graph="docs/tickets/graph.json"
[ -f "$graph" ] || { echo "MISMATCH: $graph missing"; exit 1; }
jq -e 'type=="array"' "$graph" >/dev/null 2>&1 || { echo "MISMATCH: $graph is not a JSON array"; exit 1; }
bad=0
say() { echo "MISMATCH: $*"; bad=1; }
git rev-parse --verify -q integration >/dev/null || { echo "MISMATCH: branch integration missing"; exit 1; }
# worktree branches
wt_branches="$(git worktree list --porcelain | awk '/^branch /{sub("refs/heads/","",$2); print $2}')"
ids="$(jq -r '.[].id' "$graph")"
# duplicate ids
dups="$(printf '%s\n' "$ids" | sort | uniq -d)"
[ -n "$dups" ] && say "duplicate ticket ids: $(echo "$dups" | tr '\n' ' ')"
for id in $ids; do
  state="$(jq -r --arg id "$id" '.[] | select(.id==$id) | .state' "$graph" | head -1)"
  br="ticket/$id"
  has_branch=0; git rev-parse --verify -q "$br" >/dev/null && has_branch=1
  in_wt=0; printf '%s\n' "$wt_branches" | grep -qx "$br" && in_wt=1
  merged=0; [ $has_branch -eq 1 ] && git merge-base --is-ancestor "$br" integration 2>/dev/null && merged=1
  # blockers must exist
  for b in $(jq -r --arg id "$id" '.[] | select(.id==$id) | .blocked_by[]?' "$graph"); do
    printf '%s\n' "$ids" | grep -qx "$b" || say "$id blocked_by unknown ticket $b"
  done
  case "$state" in
    todo)
      [ $has_branch -eq 1 ] && say "$id is todo but branch $br exists"
      ;;
    building)
      [ $has_branch -eq 0 ] && say "$id is building but branch $br missing"
      [ $in_wt -eq 0 ] && say "$id is building but no worktree is open on $br"
      ;;
    review|merging)
      [ $has_branch -eq 0 ] && say "$id is $state but branch $br missing"
      ;;
    done)
      [ $has_branch -eq 0 ] && say "$id is done but branch $br missing (keep branches after merge)"
      [ $has_branch -eq 1 ] && [ $merged -eq 0 ] && say "$id is done but $br is not merged into integration"
      [ $in_wt -eq 1 ] && say "$id is done but a worktree is still open on $br"
      ;;
    blocked-needs-human) ;;
    *) say "$id has unknown state '$state'";;
  esac
done
# branches with no ticket
for br in $(git for-each-ref --format='%(refname:short)' refs/heads/ticket/); do
  id="${br#ticket/}"
  printf '%s\n' "$ids" | grep -qx "$id" || say "branch $br has no ticket in graph.json"
done
# worktrees on ticket branches that are not building/review/merging
for br in $wt_branches; do
  case "$br" in ticket/*) ;; *) continue;; esac
  id="${br#ticket/}"
  state="$(jq -r --arg id "$id" '.[] | select(.id==$id) | .state' "$graph" | head -1)"
  case "$state" in building|review|merging) ;; *) say "worktree open on $br but ticket state is '${state:-missing}'";; esac
done
if [ $bad -eq 0 ]; then echo "check-state: OK ($(printf '%s\n' "$ids" | grep -c . ) tickets)"; fi
exit $bad
