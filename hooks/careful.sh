#!/usr/bin/env bash
# PreToolUse hook for Bash. Best-effort string matching, not a security boundary.
#   deny: recursive rm of / or home, force-push to main/master
#   ask:  other destructive git, database, and infrastructure commands
# Anything else passes through to Claude Code's normal permission flow.
set -uo pipefail

decide() {
  jq -cn --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

input=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"[keel careful] jq is not installed, so this command could not be safety-checked."}}'
  exit 0
fi

if ! cmd=$(printf '%s' "$input" | jq -er '.tool_input.command // ""' 2>/dev/null); then
  decide ask "[keel careful] Could not parse the tool payload to safety-check this command."
fi
[ -z "$cmd" ] && exit 0

c=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')
sp='[[:space:]]'
end='([[:space:]]|;|&|\||$)'

has() { printf '%s' "$c" | grep -Eq -- "$1"; }

# rm with a recursive flag aimed at /, /*, ~, ~/, $HOME
if has "(^|[;&|[:space:]])rm$sp" && has "$sp-[a-z]*r" && \
   has "$sp(/|/\\*|~|~/|\\\$home|\\\$\\{home\\})$end"; then
  decide deny "[keel careful] Recursive delete of the root or home directory is blocked."
fi

if has "git$sp+push" && has "($sp--force|$sp-f$end|$sp\\+[a-z0-9_/.-]*(main|master)$end)" && \
   has "(main|master)$end"; then
  decide deny "[keel careful] Force-push to main/master is blocked. Push a branch and open a PR."
fi

reasons=()
has "git$sp+push.*($sp--force|$sp-f$end)"                 && reasons+=("force-push rewrites remote history")
has "git$sp+reset$sp+--hard"                              && reasons+=("git reset --hard discards uncommitted work")
has "git$sp+clean$sp+-[a-z]*f"                            && reasons+=("git clean deletes untracked files")
printf '%s' "$cmd" | grep -Eq -- "git[[:space:]]+branch[[:space:]]+(.*[[:space:]])?(-D|--delete[[:space:]]+--force|-d[[:space:]]+-f)" \
                                                          && reasons+=("git branch -D deletes an unmerged branch")
has "git$sp+(checkout|restore)$sp+(--$sp+)?\\.$end"        && reasons+=("discards all local changes")
has "$sp--no-verify"                                      && reasons+=("--no-verify skips the repo's checks (keel principle 7)")
has "drop$sp+(table|database|schema)"                     && reasons+=("drops database objects")
has "truncate$sp+table"                                   && reasons+=("truncates a table")
has "kubectl$sp+delete"                                   && reasons+=("kubectl delete removes cluster resources")
has "terraform$sp+(destroy|apply$sp.*-destroy)"           && reasons+=("terraform destroy removes infrastructure")
has "helm$sp+(uninstall|delete)"                          && reasons+=("helm uninstall removes a release")

if [ ${#reasons[@]} -gt 0 ]; then
  msg=$(printf '%s; ' "${reasons[@]}")
  decide ask "[keel careful] ${msg%; }. Confirm this is intended."
fi

exit 0
