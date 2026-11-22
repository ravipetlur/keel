#!/usr/bin/env bash
# Stop hook. Active only while a keel task is open (.work/current exists).
# For M and L tasks, blocks finishing:
#   - in build or later without a tracker: line in task.md,
#   - in build or later without "Counsel verdict: approved" in shape.md
#     (or in task.md when there is no shape.md, as after debug),
#   - in prove, ship or done while .work/<slug>/evidence/ is empty.
# Lets the stop through on the second attempt (stop_hook_active) so it can never loop.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || root="$cwd"
[ -f "$root/.work/current" ] || exit 0
slug=$(tr -d '[:space:]' < "$root/.work/current")
task="$root/.work/$slug/task.md"
[ -n "$slug" ] && [ -f "$task" ] || exit 0

field() { sed -n "s/^$1:[[:space:]]*//p" "$task" | head -n1 | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'; }
size=$(field size)
phase=$(field phase)

case "$size" in M|L) ;; *) exit 0 ;; esac
case "$phase" in BUILD|PROVE|SHIP|LEARN|DONE) ;; *) exit 0 ;; esac

dir="$root/.work/$slug"
lc=$(printf '%s' "$phase" | tr '[:upper:]' '[:lower:]')
missing=()

grep -qE '^tracker:[[:space:]]*[^[:space:]]' "$task" \
  || missing+=("no tracker: line in task.md. Open the pinned tracker (see the track skill), or write 'tracker: none (<reason>)' if the Artifact tool is unavailable.")

plan="$dir/shape.md"; [ -f "$plan" ] || plan="$task"
grep -qiE '^Counsel verdict:[[:space:]]*approved' "$plan" 2>/dev/null \
  || missing+=("$(basename "$plan") has no 'Counsel verdict: approved' line. Build starts only after Fable 5.2 approves the plan (see section 0 of the keel skill).")

case "$phase" in
  PROVE|SHIP|DONE)
    ev="$dir/evidence"
    [ -d "$ev" ] && [ -n "$(find "$ev" -type f -size +0 2>/dev/null | head -n1)" ] \
      || missing+=(".work/$slug/evidence/ is empty. Save the verify output and the real-surface check there (see the prove skill).")
    ;;
esac

[ ${#missing[@]} -eq 0 ] && exit 0

reason="[keel] Task '$slug' (size $size) is in phase $lc but:"
for m in "${missing[@]}"; do reason+=$'\n- '"$m"; done
reason+=$'\n'"If you are only pausing to ask the user something, say so and stop again; a second stop is let through."
jq -cn --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
