#!/usr/bin/env bash
# Stop hook. Active only while a keel task is open (.work/current exists).
# Blocks finishing an M or L task in prove, ship or done while
# .work/<slug>/evidence/ is empty. Lets the stop through on the second attempt
# (stop_hook_active) so it can never loop.
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
case "$phase" in PROVE|SHIP|DONE) ;; *) exit 0 ;; esac

ev="$root/.work/$slug/evidence"
if [ -d "$ev" ] && [ -n "$(find "$ev" -type f -size +0 2>/dev/null | head -n1)" ]; then
  exit 0
fi

reason="[keel] Task '$slug' (size $size) is in phase $(printf '%s' "$phase" | tr '[:upper:]' '[:lower:]') but .work/$slug/evidence/ is empty. Save the verify output and the real-surface check there before finishing (see the prove skill). If you are only pausing to ask the user something, say so and stop again; a second stop is let through."
jq -cn --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
