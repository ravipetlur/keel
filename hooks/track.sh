#!/usr/bin/env bash
# keel track hook. One script for every tracking hook event; see docs/tracking.md.
# Active only while a keel task is open (.work/current exists). It:
#   - appends what happens to .work/<slug>/events.jsonl: owner writes, dispatches,
#     returns, commits, phase changes, counsel approval, tracker writes,
#     heartbeats and the session's own lifecycle;
#   - refuses to dispatch a unit (PreToolUse on Agent) unless its owner was
#     written to the tracker since the unit's last dispatch;
#   - blocks a Stop while board-changing events have not reached the tracker;
#   - tells a starting or resuming session its id, its open units and their leases.
# The gate and the Stop check arm only after this hook has seen a write to the
# task's tracker, so a setup where those writes are invisible to hooks is never
# blocked. Off switches: KEEL_TRACK=off (all of it), KEEL_TRACK_GATE=off (gate and
# Stop check). KEEL_BEAT_SECS sets the heartbeat interval per agent (default 60).
set -uo pipefail
[ "${KEEL_TRACK:-on}" = "off" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
fields=$(printf '%s' "$input" | jq -r '[.hook_event_name, .cwd, .session_id, .agent_id, .agent_type, .tool_name, .stop_hook_active, .source, .reason, .trigger]
  | map(if . == null then "" else tostring end) | join("\u001f")' 2>/dev/null) || exit 0
IFS=$'\x1f' read -r event cwd sid aid atype tool active source reason trigger <<< "$fields"

[ -n "$cwd" ] || cwd=$PWD
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || root="$cwd"
[ -f "$root/.work/current" ] || exit 0
slug=$(tr -d '[:space:]' < "$root/.work/current")
# .work/ can arrive inside a cloned repo, so never follow a link planted there: the slug must
# be a plain name, and nothing this hook writes to may be a symbolic link.
case "$slug" in ''|.|..|*[!A-Za-z0-9_.-]*) exit 0 ;; esac
dir="$root/.work/$slug"; task="$dir/task.md"
[ -f "$task" ] || exit 0
log="$dir/events.jsonl"; st="$dir/.track"
for p in "$root/.work" "$dir" "$st" "$log"; do [ -L "$p" ] && exit 0; done
mkdir -p "$st" 2>/dev/null || exit 0

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ); epoch=$(date +%s)
sess=${sid:0:8}; ag=${aid:-main}
beat_secs=${KEEL_BEAT_SECS:-60}; case "$beat_secs" in ''|*[!0-9]*) beat_secs=60 ;; esac

tracker=$(sed -n 's/^tracker:[[:space:]]*//p' "$task" | head -n1 | tr -d "[:space:]\"'")
case "$tracker" in http*) ;; *) tracker="" ;; esac
art_id() { local u=${1%%\?*}; u=${u%/}; printf '%s' "${u##*/}"; }
tracker_id=$(art_id "$tracker")

# Events that change what the board shows. They must reach the tracker.
SYNC='["unit.dispatched","unit.returned","unit.committed","phase.changed","counsel.approved"]'

safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'; }
put() { [ -L "$1" ] || printf '%s\n' "$2" > "$1" 2>/dev/null; } # write a state file, never through a link
field() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
emit() { # type, unit ("" for none), data (JSON object, optional)
  local d=${3:-}; [ -n "$d" ] || d='{}'
  jq -cn --arg at "$ts" --arg type "$1" --arg s "$sess" --arg a "$ag" --arg u "$2" --argjson d "$d" \
    '{at:$at, type:$type, session:$s, agent:$a} + (if $u == "" then {} else {unit:$u} end) + (if $d == {} then {} else {data:$d} end)' \
    >> "$log" 2>/dev/null
}
events() { [ -f "$log" ] && jq -cR 'fromjson? // empty' "$log" 2>/dev/null; }
armed() { [ "${KEEL_TRACK_GATE:-on}" != "off" ] && [ -n "$tracker" ] && [ -f "$log" ] && grep -q '"type":"tracker.write"' "$log"; }
unit_in() { printf '%s' "$1" | grep -ioE 'keel-unit:[[:space:]]*[A-Za-z0-9_.-]+' | head -n1 | sed -E 's/^[^:]*:[[:space:]]*//; s/[.-]+$//'; }
phase_now() { sed -n 's/^phase:[[:space:]]*//p' "$task" | head -n1 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]'; }

unsynced() { # one plain-words line per board change logged since the last tracker write
  events | jq -rs --argjson sync "$SYNC" '
    ([to_entries[] | select(.value.type == "tracker.write") | .key] | max // -1) as $w
    | .[($w + 1):][] | select(.type | IN($sync[]))
    | if .type == "phase.changed" then "phase is now \(.data.phase)"
      elif .type == "counsel.approved" then "counsel approved the plan"
      else "\(.unit) \(.type | sub("^unit\\."; ""))" end' 2>/dev/null
}
summary() { printf '%s\n' "$1" | head -n 6 | paste -sd ';' - | sed 's/;/; /g'; }
changes() { local n; n=$(printf '%s\n' "$1" | wc -l | tr -d ' '); [ "$n" = 1 ] && echo "1 board change" || echo "$n board changes"; }

check_files() { # phase changes and counsel approval, read from the task's own files
  local ph was file=""
  ph=$(phase_now); was=$(cat "$st/phase" 2>/dev/null || true)
  if [ -n "$ph" ] && [ "$ph" != "$was" ]; then
    emit phase.changed "" "$(jq -cn --arg p "$ph" '{phase:$p}')"
    put "$st/phase" "$ph"
  fi
  for f in "$dir/shape.md" "$task"; do
    grep -qiE '^Counsel verdict:[[:space:]]*approved' "$f" 2>/dev/null && { file=${f##*/}; break; }
  done
  if [ -n "$file" ]; then
    if [ "$(cat "$st/counsel" 2>/dev/null)" != approved ]; then
      emit counsel.approved "" "$(jq -cn --arg f "$file" '{file:$f}')"
      put "$st/counsel" approved
    fi
  else
    rm -f "$st/counsel"
  fi
}

beat() { # at most one heartbeat per agent per $beat_secs
  local f last
  f="$st/beat-$(safe "$ag")"; last=$(cat "$f" 2>/dev/null || echo 0)
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  [ $((epoch - last)) -ge "$beat_secs" ] || return 0
  put "$f" "$epoch"
  emit heartbeat "$(cat "$st/agent-$(safe "$ag")" 2>/dev/null || true)"
}

since_dispatch() { # unit, event type: true when that event is newer than the unit's last dispatch
  events | jq -es --arg u "$1" --arg t "$2" '
    [to_entries[] | select(.value.unit == $u)] as $e
    | ([$e[] | select(.value.type == $t) | .key] | max // -1) as $a
    | ([$e[] | select(.value.type == "unit.dispatched") | .key] | max // -1) as $d
    | $a > $d' >/dev/null 2>&1
}

pre_agent() {
  local prompt model stype desc unit data reason
  prompt=$(field '.tool_input.prompt'); model=$(field '.tool_input.model')
  stype=$(field '.tool_input.subagent_type'); desc=$(field '.tool_input.description')
  unit=$(unit_in "$prompt")
  data=$(jq -cn --arg m "$model" --arg t "$stype" --arg d "${desc:0:120}" \
    '{} + (if $m == "" then {} else {model:$m} end) + (if $t == "" then {} else {agentType:$t} end) + (if $d == "" then {} else {description:$d} end)')
  if [ -z "$unit" ]; then emit agent.dispatched "" "$data"; return 0; fi
  if armed && ! since_dispatch "$unit" unit.assigned; then
    emit dispatch.refused "$unit"
    reason="[keel track] $unit has no owner recorded in the tracker since its last dispatch, so this dispatch is refused. Record the owner first: one ArtifactData update to tasks/$unit setting assignee {session: \"$sess\", agent: \"builder\", model}, assignedBy, a new assignedAt, leaseUntil and attempt (track skill, section 4). Then dispatch again. If the tracker already shows this owner, the hook could not see the write: tell the user, and set KEEL_TRACK_GATE=off to turn the gate off."
    jq -cn --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    return 0
  fi
  emit unit.dispatched "$unit" "$data"
}

agent_post() { # ties the new subagent's id to its unit; nudges about untagged builders
  local prompt unit model agid resp
  prompt=$(field '.tool_input.prompt'); unit=$(unit_in "$prompt"); model=$(field '.tool_input.model')
  if [ -z "$unit" ]; then
    if [ -n "$tracker" ] && [ "$(phase_now)" = build ] && printf '%s' "$model" | grep -qi sonnet; then
      jq -cn '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:"[keel track] That builder was dispatched without a keel-unit line, so its work cannot be tied to a tracker task. If it builds a unit, put \"keel-unit: <task id>\" in the brief and record the owner in the tracker before dispatching (track skill, section 4)."}}'
    fi
    return 0
  fi
  resp=$(field '.tool_response | if type == "string" then . else tojson end')
  agid=$(field '[.tool_response | .. | objects | (.agentId // .agent_id // empty)] | first')
  [ -n "$agid" ] || agid=$(printf '%s' "$resp" | grep -oE 'agent_?[Ii]d"?[: ]+"?[A-Za-z0-9_-]+' | head -n1 | sed -E 's/.*[: "]+//')
  if [ -z "$agid" ]; then
    # No id to wait for. A foreground call returns only once its builder is done; a background launch says so.
    printf '%s' "${resp:0:500}" | grep -qiE 'async|launch|background' && return 0
    since_dispatch "$unit" unit.returned || emit unit.returned "$unit"
    return 0
  fi
  put "$st/agent-$(safe "$agid")" "$unit"
  # A foreground builder has already stopped by now, and its SubagentStop could not name the unit.
  if events | jq -es --arg a "$agid" 'any(.[]; .type == "agent.returned" and .agent == $a)' >/dev/null 2>&1 \
     && ! events | jq -es --arg a "$agid" --arg u "$unit" 'any(.[]; .type == "unit.returned" and .agent == $a and .unit == $u)' >/dev/null 2>&1; then
    local ag=$agid
    emit unit.returned "$unit"
  fi
}

sub_stop() {
  local unit
  unit=$(cat "$st/agent-$(safe "$ag")" 2>/dev/null || true)
  [ -n "$unit" ] || unit=$(unit_in "$(field '.last_assistant_message')")
  local data; data=$(jq -cn --arg t "$atype" 'if $t == "" then {} else {agentType:$t} end')
  if [ -n "$unit" ]; then emit unit.returned "$unit" "$data"; else emit agent.returned "" "$data"; fi
}

tracker_write() { # a write to this task's tracker: log it, and any owner it records
  [ -n "$tracker_id" ] || return 0
  [ "$(art_id "$(field '.tool_input.url')")" = "$tracker_id" ] || return 0
  case "$(field '.tool_input.action')" in set|update|str_replace|delete|batch) ;; *) return 0 ;; esac
  local resp; resp=$(field '.tool_response | if type == "string" then . else tojson end')
  if printf '%s' "${resp:0:300}" | grep -qiE '(wrote|writes|written) nothing|nothing (was |is )?written|not written|(write|writes|batch)( was| is)? refused|refused until'; then
    emit tracker.write_failed ""
    return 0
  fi
  local entries docs="" coll doc op has lease by at fp
  entries=$(printf '%s' "$input" | jq -r '.tool_input as $t
    | (if $t.action == "batch" then ($t.writes // []) else [{op: $t.action, collection: $t.collection, doc_id: $t.doc_id, data: $t.data, file_path: $t.file_path}] end)[]
    | [.collection, .doc_id, .op,
       (if .data.assignee != null and ((.data.assignee | type) != "object" or .data.assignee.__delete__ != true) then "1" else "0" end),
       .data.leaseUntil, .data.assignedBy, .data.assignedAt, .file_path]
    | map(if . == null then "" else tostring end) | join("\u001f")' 2>/dev/null)
  while IFS=$'\x1f' read -r coll doc op has lease by at fp; do
    [ -n "$coll$doc" ] || continue
    docs+="$coll/$doc"$'\n'
    if [ "$has" = 0 ] && [ -n "$fp" ] && [ -f "$fp" ]; then
      IFS=$'\x1f' read -r has lease by at <<< "$(jq -r '[(if .assignee != null then "1" else "0" end), .leaseUntil, .assignedBy, .assignedAt] | map(if . == null then "" else tostring end) | join("\u001f")' "$fp" 2>/dev/null)"
    fi
    # A new owner is an assignee with a new assignedAt; a lease extension or a resent assignee is not.
    if [ "$coll" = tasks ] && [ "$has" = 1 ] && [ -n "$at" ] && { [ "$op" = set ] || [ "$op" = update ]; } \
       && [ "$at" != "$(cat "$st/assigned-$(safe "$doc")" 2>/dev/null)" ]; then
      put "$st/assigned-$(safe "$doc")" "$at"
      emit unit.assigned "$doc" "$(jq -cn --arg l "$lease" --arg b "$by" --arg w "$at" '{assignedAt:$w} + (if $l == "" then {} else {leaseUntil:$l} end) + (if $b == "" then {} else {by:$b} end)')"
    fi
  done <<< "$entries"
  emit tracker.write "" "$(printf '%s' "$docs" | jq -cR -s 'split("\n") | map(select(. != "")) | {docs: .}')"
}

commit_check() { # a new commit; Keel-Unit trailers name the units it completes
  printf '%s' "$(field '.tool_input.command')" | grep -Eq 'git([[:space:]]+-[cC][[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)' || return 0
  local line sha units subj data u
  line=$(git -C "$root" log -1 --format='%H%x1f%(trailers:key=Keel-Unit,valueonly,separator=%x2C)%x1f%s' 2>/dev/null) || return 0
  IFS=$'\x1f' read -r sha units subj <<< "$line"
  [ -n "$sha" ] && [ "$sha" != "$(cat "$st/last-commit" 2>/dev/null)" ] || return 0
  put "$st/last-commit" "$sha"
  data=$(jq -cn --arg c "${sha:0:12}" --arg s "${subj:0:120}" '{commit:$c, subject:$s}')
  if [ -z "$units" ]; then emit commit "" "$data"; return 0; fi
  printf '%s\n' "$units" | tr ',' '\n' | while read -r u; do [ -z "$u" ] || emit unit.committed "$u" "$data"; done
}

open_units() { # units dispatched since their last commit, with their lease state
  events | jq -rs '
    def epoch: tostring | sub("\\.[0-9]+"; "") | (try fromdateiso8601 catch null);
    map(select(.unit != null and (.type | IN("unit.assigned", "unit.dispatched", "unit.returned", "unit.committed"))))
    | group_by(.unit)[]
    | . as $ev
    | ([range(0; length) | select($ev[.].type == "unit.committed")] | max // -1) as $c
    | $ev[($c + 1):] as $after
    | select(any($after[]; .type == "unit.dispatched"))
    | ([$after[] | select(.type == "unit.dispatched" or .type == "unit.returned")] | last) as $last
    | ([$after[] | select(.type == "unit.assigned")] | last | .data.leaseUntil // "") as $lease
    | ($lease | if . == "" then null else epoch end) as $le
    | "- \($ev[0].unit): "
      + (if $last.type == "unit.returned" then "back from its builder since \($last.at), waiting for review"
         else "with a builder since \($last.at) (session \($last.session))"
           + (if $le == null then ", no lease recorded" elif $le < now then ", lease ran out at \($lease)" else ", lease until \($lease)" end)
         end)' 2>/dev/null
}

session_start() {
  emit session.started "" "$(jq -cn --arg s "$source" '{source:$s}')"
  [ -e "$st/last-commit" ] || put "$st/last-commit" "$(git -C "$root" rev-parse HEAD 2>/dev/null)"
  local ctx open list
  ctx="[keel track] Task '$slug' is open. This session's id is $sess: write it as assignee.session when you record an owner in the tracker."
  if [ -n "$tracker" ]; then
    open=$(open_units)
    [ -z "$open" ] || ctx+=$'\n'"Open units in this checkout's event log:"$'\n'"$open"
    list=$(unsynced)
    [ -z "$list" ] || ctx+=$'\n'"Not in the tracker yet ($(changes "$list")): $(summary "$list"). Sync them first (track skill, section 4)."
    if printf '%s' "$open" | grep -q 'lease ran out'; then
      ctx+=$'\n'"For each unit whose lease ran out: if this session owned it, record the owner again and re-dispatch; if another session owns it, follow the claim rules (track skill, section 5)."
    fi
    case "$source" in startup|resume) ctx+=$'\n'"Units leased by other sessions show only in the tracker: read tasks/ there and apply the same claim rules to any lease that ran out." ;; esac
  fi
  jq -cn --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
}

stop_check() {
  [ "$active" = true ] && return 0
  armed || return 0
  local list
  list=$(unsynced); [ -n "$list" ] || return 0
  jq -cn --arg r "[keel track] The tracker is $(changes "$list") behind: $(summary "$list"). Write them to the tracker now (track skill, section 4, one ArtifactData batch), then finish. If you are only pausing to ask the user something, say so and stop again; a second stop is let through." \
    '{decision:"block", reason:$r}'
}

case "$event" in
  PreToolUse)
    case "$tool" in Agent|Task) pre_agent ;; esac ;;
  PostToolUse)
    beat
    case "$tool" in
      ArtifactData) tracker_write ;;
      Agent|Task) agent_post ;;
      Bash) commit_check; check_files ;;
      Edit|Write|MultiEdit|NotebookEdit) check_files ;;
    esac ;;
  SubagentStop) sub_stop ;;
  SessionStart) session_start ;;
  Stop) check_files; emit turn.ended ""; stop_check ;;
  StopFailure) emit session.failed "" "$(field '(.error // .reason // .message) | tostring | .[0:200] | {error: .}')" ;;
  SessionEnd) emit session.ended "" "$(jq -cn --arg r "$reason" '{reason:$r}')" ;;
  PreCompact) emit session.compacting "" "$(jq -cn --arg t "$trigger" '{trigger:$t}')" ;;
esac
exit 0
