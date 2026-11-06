#!/usr/bin/env bash
# PostToolUse hook for Edit, Write and MultiEdit. Active only while a keel task
# is open (.work/current exists). Detects gate-weakening markers that are new
# relative to HEAD, logs each one once to .work/<slug>/gates.tsv, and reminds
# the agent that each needs a reason the user will see in the PR.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$file" ] && [ -f "$file" ] || exit 0
[ -n "$cwd" ] || cwd=$(dirname "$file")

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || root="$cwd"
[ -f "$root/.work/current" ] || exit 0
slug=$(tr -d '[:space:]' < "$root/.work/current")
[ -n "$slug" ] || exit 0

case "$file" in
  *.md|*.markdown|*.txt|*.tsv|"$root"/.work/*) exit 0 ;;
esac

# label<TAB>extended regex
patterns='test skipped	(\.skip\(|\bxit\(|\bxdescribe\(|\bxtest\(|@pytest\.mark\.skip|pytest\.skip\(|\bt\.Skip\(|@Disabled|@Ignore\b|#\[ignore\])
focused test (others stop running)	(\b(it|describe|test)\.only\(|\bfit\(|\bfdescribe\()
type check suppressed	(@ts-ignore|@ts-nocheck|@ts-expect-error|#[[:space:]]*type:[[:space:]]*ignore|#[[:space:]]*pyright:[[:space:]]*ignore)
lint suppressed	(eslint-disable|biome-ignore|#[[:space:]]*noqa|//[[:space:]]*nolint|#[[:space:]]*pylint:[[:space:]]*disable|@SuppressWarnings|#\[allow\()'

rel=${file#"$root"/}
before=$(git -C "$root" show "HEAD:$rel" 2>/dev/null || true)

log="$root/.work/$slug/gates.tsv"
mkdir -p "$root/.work/$slug"
found=()
while IFS=$'\t' read -r label regex; do
  now=$(grep -Ec -- "$regex" "$file" 2>/dev/null || true)
  was=$(printf '%s' "$before" | grep -Ec -- "$regex" 2>/dev/null || true)
  now=${now:-0}; was=${was:-0}
  if [ "$now" -gt "$was" ]; then
    if ! { [ -f "$log" ] && awk -F'\t' -v f="$rel" -v l="$label" '$2==f && $3==l {x=1} END {exit !x}' "$log"; }; then
      printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rel" "$label" "needs reason" >> "$log"
    fi
    found+=("$label")
  fi
done <<< "$patterns"

[ ${#found[@]} -eq 0 ] && exit 0
list=$(printf '%s, ' "${found[@]}")
msg="[keel gate-guard] $rel now has more of: ${list%, } than at HEAD. That weakens a gate (keel principle 7). If it is truly needed, replace 'needs reason' in .work/$slug/gates.tsv with the reason; ship lists it in the PR for the user to approve. Otherwise remove it and fix the underlying problem."
jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
exit 0
