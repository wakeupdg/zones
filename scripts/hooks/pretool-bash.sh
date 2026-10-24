#!/usr/bin/env bash
# PreToolUse(Bash) hook: any shell segment that starts with `swift build`, `swift test`
# or `xcodebuild` is rewritten to run through scripts/q.sh, so only the last 60 lines reach the agent.
set -u
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0
case "$cmd" in *q.sh*) exit 0;; esac
if ! printf '%s' "$cmd" | grep -Eq '(^|&&|\|\||;|\|)[[:space:]]*(swift[[:space:]]+(build|test)|xcodebuild)([[:space:]]|$)'; then
  exit 0
fi
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
root="$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null || echo "${CLAUDE_PROJECT_DIR:-.}")"
q="$root/scripts/q.sh"
[ -x "$q" ] || exit 0
printf '%s' "$input" | jq --arg q "$q" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "routed through scripts/q.sh",
    updatedInput: (.tool_input + { command: (($q|@sh) + " bash -c " + (.tool_input.command|@sh)) })
  }
}'
