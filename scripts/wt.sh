#!/usr/bin/env bash
# wt.sh — ticket worktrees at a fixed path next to the main checkout.
# Usage: scripts/wt.sh path <id> | add <id> | remove <id> | list
set -euo pipefail
common="$(git rev-parse --git-common-dir)"; case "$common" in /*) ;; *) common="$PWD/$common";; esac
main="$(cd "$(dirname "$common")" && pwd)"
base="$(dirname "$main")/.zones-worktrees"
cmd="$1"; id="${2:-}"
case "$cmd" in
  path) echo "$base/$id";;
  add)
    mkdir -p "$base"
    if [ -d "$base/$id" ]; then echo "$base/$id"; exit 0; fi
    if git -C "$main" rev-parse --verify -q "ticket/$id" >/dev/null; then
      git -C "$main" worktree add -q "$base/$id" "ticket/$id"
    else
      git -C "$main" worktree add -q -b "ticket/$id" "$base/$id" integration
    fi
    echo "$base/$id";;
  remove)
    git -C "$main" worktree remove --force "$base/$id" 2>/dev/null || true
    git -C "$main" worktree prune
    echo "removed $id";;
  list) git -C "$main" worktree list;;
  *) echo "usage: wt.sh path|add|remove <id> | list" >&2; exit 64;;
esac
