#!/usr/bin/env bash
# Shared helpers for PreToolUse guard hooks. Reads the hook payload from stdin.

HOOK_INPUT="$(cat)"

hook_field() {
  printf '%s' "$HOOK_INPUT" | jq -r "$1 // empty"
}

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

allow() {
  exit 0
}

# Splits a shell command on ; && || | and newlines, one segment per line.
command_segments() {
  printf '%s\n' "$1" | perl -pe 's/(&&|\|\||;|\|)/\n/g; s/^[ \t]+|[ \t]+$//mg' | grep -v '^$'
}
