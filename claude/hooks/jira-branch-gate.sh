#!/usr/bin/env bash
# PreToolUse gate: deny `git commit` / `git push` from branches without a JIRA key.
# Enforces the CLAUDE.md rule "Every piece of work traces to a JIRA ticket".
input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
printf '%s' "$cmd" | grep -qE '\bgit\b[^|;&]*\b(commit|push)\b' || exit 0
dir=$(printf '%s' "$input" | jq -r '.cwd // "."')
# Prefer an explicit `git -C <dir>` target over the session cwd (which the harness
# pins to the project root, misreporting the branch for out-of-tree commits).
cdir=$(printf '%s' "$cmd" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+"([^"]+)".*/\1/p')
[ -z "$cdir" ] && cdir=$(printf '%s' "$cmd" | sed -nE 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]";&|]+).*/\1/p')
[ -n "$cdir" ] && dir=$cdir
# Playground repos hold experiments and windots is personal dotfiles, not delivery work, so neither traces to a ticket.
# Resolved from the repo root, not $dir, so a commit run from a subdirectory is
# exempt too. An unresolvable root takes no exemption and falls through.
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
case "$root" in */pageup/playground/*|*/windots) exit 0 ;; esac
branch=$(git -C "$dir" branch --show-current 2>/dev/null) || exit 0
[ -n "$branch" ] || exit 0
printf '%s' "$branch" | grep -qE '[A-Z][A-Z0-9]*-[0-9]+' && exit 0
jq -n --arg b "$branch" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("JIRA gate: branch \"" + $b + "\" has no JIRA key. Per CLAUDE.md, create a branch like feat/PE-123-short-desc off main, or ask the user for a ticket.")}}'
