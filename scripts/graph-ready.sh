#!/usr/bin/env bash
# graph-ready.sh — print ids of todo tickets whose blockers are all done (the ready set).
set -euo pipefail
common="$(git rev-parse --git-common-dir)"; case "$common" in /*) ;; *) common="$PWD/$common";; esac
main="$(cd "$(dirname "$common")" && pwd)"
graph="${ZONES_GRAPH:-$main/docs/tickets/graph.json}"
jq -r '. as $g | map(select(.state=="todo")) | map(select(all(.blocked_by[]?; . as $b | ($g | map(select(.id==$b and .state=="done")) | length) == 1))) | .[].id' "$graph"
