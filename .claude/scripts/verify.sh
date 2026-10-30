#!/usr/bin/env bash
# Deterministic quality gate. Runs the Rails app's zeitwerk check, lint, security scan and tests in order
# and stops at the first failure, printing a compact summary instead of the full log.
#
# Usage: verify.sh [--quick] [--max-lines N]
#   --quick      zeitwerk:check only (Ruby's closest equivalent to a typecheck)
#   --max-lines  lines of failure output to print (default 40)
#
# Full logs are kept in .claude/plans/.verify/<step>.log for agents that need more detail.

set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" || exit 2

quick=false
max_lines=40
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) quick=true ;;
    --max-lines) shift; max_lines="${1:-40}" ;;
    *) echo "verify: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

if [ ! -f Gemfile ]; then
  echo "verify: SKIP - no Gemfile yet, nothing to check."
  exit 0
fi

has_gem() {
  grep -Eq "^[[:space:]]*gem[[:space:]]+[\"']$1[\"']" Gemfile
}

steps=()
[ -x bin/rails ] && steps+=(zeitwerk)
if ! $quick; then
  { has_gem rubocop-rails-omakase || has_gem rubocop; } && steps+=(lint)
  [ -x bin/brakeman ] && steps+=(security)
  has_gem rspec-rails && steps+=(test)
fi

if [ ${#steps[@]} -eq 0 ]; then
  echo "verify: SKIP - no bin/rails, rubocop, brakeman or rspec-rails found."
  exit 0
fi

log_dir="$root/.claude/plans/.verify"
mkdir -p "$log_dir"

for step in "${steps[@]}"; do
  log="$log_dir/$step.log"
  start=$(date +%s)
  case "$step" in
    zeitwerk) bin/rails zeitwerk:check >"$log" 2>&1 ;;
    lint) bundle exec rubocop --format simple >"$log" 2>&1 ;;
    security) bin/brakeman --quiet --no-pager >"$log" 2>&1 ;;
    test) CI=true RAILS_ENV=test bundle exec rspec --format progress >"$log" 2>&1 ;;
  esac
  code=$?
  secs=$(( $(date +%s) - start ))

  if [ $code -eq 0 ]; then
    echo "verify: PASS $step (${secs}s)"
    continue
  fi

  echo "verify: FAIL $step (exit $code, ${secs}s) - full log: ${log#"$root"/}"
  echo "----"
  errors="$(grep -E '(Error|error:|Failure|FAIL|expected file|rspec \./|^[CWEF]:|^== [^=]+ ==$|^(Confidence|Message|File|Line):|\.rb:[0-9]+)' "$log" | grep -v -E '^[[:space:]]*# |^Errors: 0$|^== (Brakeman Report|Overview|Warning Types|Warnings) ==$' | head -n "$max_lines")"
  if [ -n "$errors" ]; then
    printf '%s\n' "$errors"
  else
    tail -n "$max_lines" "$log"
  fi
  echo "----"
  files="$(grep -o -E '(app|lib|spec|config|db)/[A-Za-z0-9_./-]+\.rb' "$log" | sort -u | head -n 20)"
  if [ -n "$files" ]; then
    echo "files:"
    printf '  %s\n' $files
  fi
  exit 1
done

echo "verify: ALL PASS (${steps[*]})"
