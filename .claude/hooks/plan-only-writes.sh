#!/usr/bin/env bash
# Planning and review agents may write only inside .claude/plans/.
source "$(dirname "$0")/_lib.sh"

case "$(hook_field '.tool_name')" in
  Write|Edit|MultiEdit|NotebookEdit) ;;
  *) allow ;;
esac

path="$(hook_field '.tool_input.file_path // .tool_input.notebook_path')"
[ -n "$path" ] || allow

root="${CLAUDE_PROJECT_DIR:-$(hook_field '.cwd')}"
case "$path" in
  /*) abs="$path" ;;
  *) abs="$root/$path" ;;
esac

case "$abs" in
  *"/../"*) deny "Blocked: '$path'. Paths containing '..' are not allowed." ;;
  "$root/.claude/plans/"*) allow ;;
esac

deny "Blocked: '$path'. This agent may only write under .claude/plans/. Put findings or plan changes in the branch plan.md and report back."
