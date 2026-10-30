#!/usr/bin/env bash
# Sub-agents may edit code and run checks, but only the coordinator commits, pushes or posts to a PR.
source "$(dirname "$0")/_lib.sh"

[ "$(hook_field '.tool_name')" = "Bash" ] || allow
cmd="$(hook_field '.tool_input.command')"
[ -n "$cmd" ] || allow

blocked='^(sudo[[:space:]]+)?(git[[:space:]]+(commit|push|reset[[:space:]]+--hard|rebase|stash|clean|checkout[[:space:]]+--|restore|branch[[:space:]]+-[dD]|tag)|gh[[:space:]]+pr[[:space:]]+(create|comment|merge|close|review|edit))'

while IFS= read -r seg; do
  if printf '%s' "$seg" | grep -Eq "$blocked"; then
    deny "Blocked: '$seg'. Sub-agents must not change git history or post to PRs. Leave changes in the working tree and report back; the coordinator commits."
  fi
done < <(command_segments "$cmd")

allow
