#!/usr/bin/env bash
# Read-only agents (analyst, reviewer) may only inspect the repo and PRs from the shell.
source "$(dirname "$0")/_lib.sh"

[ "$(hook_field '.tool_name')" = "Bash" ] || allow
cmd="$(hook_field '.tool_input.command')"
[ -n "$cmd" ] || allow

stripped="$(printf '%s' "$cmd" | perl -pe 's/2>\/dev\/null|2>&1//g')"
if printf '%s' "$stripped" | grep -Eq '>|\$\(|`'; then
  deny "Blocked: redirection or command substitution is not allowed for read-only agents. Use Read, Grep and Glob instead."
fi

allowed='^(git[[:space:]]+(diff|log|show|status|blame|merge-base|rev-parse|branch[[:space:]]+--show-current|ls-files)|gh[[:space:]]+pr[[:space:]]+(view|diff|list|checks)|gh[[:space:]]+api|ls|tree|rg|wc|head|tail|sort|uniq|jq)([[:space:]]|$)'

while IFS= read -r seg; do
  if ! printf '%s' "$seg" | grep -Eq "$allowed"; then
    deny "Blocked: '$seg'. This agent is read-only: allowed shell commands are read-only git, gh pr view/diff/list/checks, gh api (GET or GraphQL query), ls, tree, rg, wc, head, tail, sort, uniq, jq."
  fi
  if printf '%s' "$seg" | grep -Eq '^gh[[:space:]]+api[[:space:]]+graphql([[:space:]]|$)'; then
    if printf '%s' "$seg" | grep -Eiq 'mutation|--input|(-X|--method)[[:space:]]*(PUT|PATCH|DELETE)'; then
      deny "Blocked: '$seg'. Only GraphQL queries are allowed; mutations are not."
    fi
    continue
  fi
  if printf '%s' "$seg" | grep -Eq '^gh[[:space:]]+api[[:space:]]' && printf '%s' "$seg" | grep -Eq '(-X|--method)[[:space:]]*(POST|PUT|PATCH|DELETE)|(^|[[:space:]])(-f|-F|--field|--raw-field|--input)([[:space:]]|=)'; then
    deny "Blocked: '$seg'. Only GET requests are allowed with gh api."
  fi
done < <(command_segments "$cmd")

allow
