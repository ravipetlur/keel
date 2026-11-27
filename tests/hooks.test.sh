#!/usr/bin/env bash
# Runs each keel hook against sample payloads and checks the decision.
# Usage: tests/hooks.test.sh
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
pass=0; fail=0

check() { # name, expected substring ("" = no output), actual
  if { [ -z "$2" ] && [ -z "$3" ]; } || { [ -n "$2" ] && printf '%s' "$3" | grep -q -- "$2"; }; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "${2:-<no output>}" "${3:-<no output>}"
  fi
}

bash_payload() { jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
careful() { bash_payload "$1" | "$HOOKS/careful.sh"; }

# careful.sh
check "rm -rf /"                 '"deny"' "$(careful 'rm -rf /')"
check "rm -rf ~"                 '"deny"' "$(careful 'sudo rm -fr ~')"
check "rm -rf \$HOME"            '"deny"' "$(careful 'rm -rf $HOME')"
check "chained rm -rf /"         '"deny"' "$(careful 'git commit -m "wip" && rm -rf /')"
check "rm -rf node_modules"      ''       "$(careful 'rm -rf node_modules')"
check "rm -rf ./build/"          ''       "$(careful 'rm -rf ./build/')"
check "force push main"          '"deny"' "$(careful 'git push --force origin main')"
check "force push -f master"     '"deny"' "$(careful 'git push -f origin master')"
check "plus refspec main"        '"deny"' "$(careful 'git push origin +main')"
check "force push branch"        '"ask"'  "$(careful 'git push --force-with-lease origin feat/x')"
check "normal push"              ''       "$(careful 'git push -u origin feat/main-menu')"
check "reset --hard"             '"ask"'  "$(careful 'git reset --hard HEAD~1')"
check "git clean -fd"            '"ask"'  "$(careful 'git clean -fd')"
check "branch -D"                '"ask"'  "$(careful 'git branch -D old')"
check "branch -d is fine"        ''       "$(careful 'git branch -d merged')"
check "checkout -- ."            '"ask"'  "$(careful 'git checkout -- .')"
check "checkout file is fine"    ''       "$(careful 'git checkout -- src/a.ts')"
check "--no-verify"              '"ask"'  "$(careful 'git commit --no-verify -m x')"
check "drop table"               '"ask"'  "$(careful 'psql -c "DROP TABLE users"')"
check "truncate table"           '"ask"'  "$(careful 'mysql -e "truncate table logs"')"
check "kubectl delete"           '"ask"'  "$(careful 'kubectl delete pod web-1')"
check "terraform destroy"        '"ask"'  "$(careful 'terraform destroy -auto-approve')"
check "plain ls"                 ''       "$(careful 'ls -la')"
check "unparseable payload"      '"ask"'  "$(printf 'not json' | "$HOOKS/careful.sh")"

# gate-guard.sh and evidence-stop.sh need a git repo with an open keel task
tmp=$(mktemp -d "${TMPDIR:-/tmp}/keel-test.XXXXXX") && [ -d "$tmp" ] || { echo "cannot create a temp dir; set TMPDIR to a writable path" >&2; exit 1; }
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
printf 'it("a", () => {})\n' > "$tmp/a.test.ts"
git -C "$tmp" add . && git -C "$tmp" -c user.email=t@t -c user.name=t commit -qm init

edit() { jq -cn --arg f "$1" --arg d "$tmp" '{tool_name:"Edit",tool_input:{file_path:$f},cwd:$d}' | "$HOOKS/gate-guard.sh"; }

printf 'it.skip("a", () => {})\n' > "$tmp/a.test.ts"
check "gate: no task open"       ''       "$(edit "$tmp/a.test.ts")"

mkdir -p "$tmp/.work/t1"; printf 't1\n' > "$tmp/.work/current"
check "gate: new skip flagged"   'test skipped'      "$(edit "$tmp/a.test.ts")"
check "gate: logged once"        '1'                 "$(edit "$tmp/a.test.ts" >/dev/null; grep -c 'test skipped' "$tmp/.work/t1/gates.tsv")"
printf '// eslint-disable-next-line\nconst x = 1 // @ts-ignore\n' > "$tmp/b.ts"
out=$(edit "$tmp/b.ts")
check "gate: lint suppression"   'lint suppressed'   "$out"
check "gate: ts-ignore"          'type check suppressed' "$out"
printf 'it("a", () => {})\n' > "$tmp/a.test.ts"
check "gate: reverted is quiet"  ''       "$(edit "$tmp/a.test.ts")"
printf 'use .skip( carefully\n' > "$tmp/notes.md"
check "gate: markdown ignored"   ''       "$(edit "$tmp/notes.md")"

stop() { jq -cn --arg d "$tmp" --argjson a "${1:-false}" '{cwd:$d,stop_hook_active:$a}' | "$HOOKS/evidence-stop.sh"; }
task() { printf -- '---\nsize: %s\nphase: %s\n%s---\n# goal\n' "$1" "$2" "${3-tracker: https://claude.ai/artifact/x\n}" > "$tmp/.work/t1/task.md"; }
approve() { printf '## Counsel (Fable 5.2)\nCounsel verdict: approved (round 1)\n' > "$tmp/.work/t1/shape.md"; }

task M shape '';  check "stop: M shape needs nothing yet" ''     "$(stop)"
task M build;     check "stop: M build without counsel" 'Counsel verdict' "$(stop)"
approve
task M build;     check "stop: M build approved passes" ''      "$(stop)"
task M build '';  check "stop: M build without tracker" 'no tracker' "$(stop)"
task M build 'tracker: none (no Artifact tool)\n'
                  check "stop: tracker none is accepted" ''     "$(stop)"
task M prove;  check "stop: M prove no evidence" '"block"' "$(stop)"
               check "stop: second stop passes" ''         "$(stop true)"
task S done '';  rm "$tmp/.work/t1/shape.md"
               check "stop: S never blocks"     ''         "$(stop)"
task L ship;   approve; mkdir -p "$tmp/.work/t1/evidence"; : > "$tmp/.work/t1/evidence/empty.txt"
               check "stop: empty file is not evidence" '"block"' "$(stop)"
printf 'ok\n' > "$tmp/.work/t1/evidence/verify.txt"
               check "stop: L ship with evidence" ''       "$(stop)"
printf '## Counsel\nRound 1: Improve\n' > "$tmp/.work/t1/shape.md"
               check "stop: L ship, counsel not approved" 'Counsel verdict' "$(stop)"
rm "$tmp/.work/t1/shape.md"
task M build;  check "stop: debug rejoin, no plan approval" 'task.md has no' "$(stop)"
printf -- '---\nsize: M\nphase: build\ntracker: u\n---\n## Plan\nx\nCounsel verdict: approved (round 1)\n' > "$tmp/.work/t1/task.md"
               check "stop: approval in task.md accepted" ''  "$(stop)"
rm "$tmp/.work/current"
task M prove;  rm -rf "$tmp/.work/t1/evidence"
               check "stop: no open task passes" ''        "$(stop)"

# track.sh: its own repo, so the evidence-stop cases above stay independent
tr_repo="$tmp/tr"; mkdir -p "$tr_repo"; git -C "$tr_repo" init -q
printf 'x\n' > "$tr_repo/f"; git -C "$tr_repo" add . && git -C "$tr_repo" -c user.email=t@t -c user.name=t commit -qm init
TURL="https://claude.ai/code/artifact/trk1"; TLOG="$tr_repo/.work/t2/events.jsonl"
trk() { # hook event, extra payload fields (JSON object)
  local x=${2:-}; [ -n "$x" ] || x='{}'
  jq -cn --arg d "$tr_repo" --arg e "$1" --argjson x "$x" '{hook_event_name:$e, cwd:$d, session_id:"sess1234abcd"} + $x' | "$HOOKS/track.sh"
}
ttask() { printf -- '---\nsize: M\nphase: %s\n%b---\n# goal\n' "$1" "${2-tracker: $TURL\n}" > "$tr_repo/.work/t2/task.md"; }
ev() { grep -c -- "$1" "$TLOG" 2>/dev/null; }
dispatch() { trk PreToolUse "$(jq -cn --arg u "$1" '{tool_name:"Agent", tool_input:{prompt:"Build it.\nkeel-unit: \($u)\n", model:"sonnet", description:"build"}}')"; }
owner() { # unit, lease, [tracker url], [tool response], [assignedAt]
  local at=${5:-at-$(od -An -N4 -tu4 /dev/urandom | tr -d ' ')}
  trk PostToolUse "$(jq -cn --arg u "$1" --arg l "$2" --arg url "${3:-$TURL}" --arg r "${4:-Updated tasks/$1 (version 4)}" --arg at "$at" \
    '{tool_name:"ArtifactData", tool_input:{action:"update", url:$url, collection:"tasks", doc_id:$u, data:{status:"building", assignee:{session:"sess1234", agent:"builder", model:"Sonnet 5.5"}, assignedAt:$at, leaseUntil:$l, attempt:1}}, tool_response:$r}')"
}
synced() { trk PostToolUse "$(jq -cn --arg url "$TURL" '{tool_name:"ArtifactData", tool_input:{action:"update", url:$url, collection:"status", doc_id:"current", data:{headline:"x"}}, tool_response:"ok"}')"; }
FUTURE="2099-01-01T00:00:00Z"; PAST="2000-01-01T00:00:00Z"

check "track: no task open"              ''              "$(trk SessionStart '{"source":"startup"}')"
check "track: nothing written without a task" ''         "$(ls "$tr_repo/.work" 2>/dev/null)"
mkdir -p "$tr_repo/.work/t2"; printf 't2\n' > "$tr_repo/.work/current"; ttask build
check "track: session start names the session" 'sess1234' "$(trk SessionStart '{"source":"startup"}')"
check "track: session start logged"      '1'             "$(ev '"type":"session.started"')"
check "track: starting phase recorded at session start" '1' "$(ev '"type":"phase.changed","session":"sess1234","agent":"main","data":{"phase":"build"}')"
check "track: gate not armed before a tracker write" '' "$(dispatch m1-t01)"
check "track: unarmed dispatch logged"   '1'             "$(ev '"type":"unit.dispatched"')"
check "track: owner write is quiet"      ''              "$(owner m1-t01 "$FUTURE")"
check "track: owner write logged"        '1'             "$(ev '"type":"unit.assigned","session":"sess1234","agent":"main","unit":"m1-t01"')"
check "track: tracker write logged"      '1'             "$(ev '"type":"tracker.write"')"
check "track: dispatch after owner write" ''             "$(dispatch m1-t01)"
check "track: second dispatch needs a new owner write" 'no owner recorded' "$(dispatch m1-t01)"
check "track: refusal logged"            '1'             "$(ev '"type":"dispatch.refused"')"
check "track: unassigned unit refused"   '"deny"'        "$(dispatch m1-t02)"
trk PostToolUse "$(jq -cn --arg url "$TURL" --arg l "$PAST" '{tool_name:"ArtifactData", tool_input:{action:"batch", url:$url, writes:[
  {op:"update", collection:"tasks", doc_id:"m1-t02", data:{assignee:{session:"sess1234"}, assignedAt:"a2", leaseUntil:$l, assignedBy:"pull"}},
  {op:"update", collection:"tasks", doc_id:"m1-t06", data:{assignee:{session:"sess1234"}, assignedAt:"a6", leaseUntil:$l}},
  {op:"set", collection:"status", doc_id:"current", data:{headline:"x"}}]}, tool_response:{ok:true}}')" >/dev/null
check "track: batch owner write counts"  ''              "$(dispatch m1-t02)"
check "track: batch keeps assignedBy"    '1'             "$(ev '"unit":"m1-t02","data":{"assignedAt":"a2","leaseUntil":"2000-01-01T00:00:00Z","by":"pull"}')"
owner m1-t03 "$FUTURE" "https://claude.ai/code/artifact/other" >/dev/null
check "track: another tracker's write ignored" '"deny"'  "$(dispatch m1-t03)"
owner m1-t03 "$FUTURE" "$TURL" "Nothing was written: tasks/m1-t03 changed, current version 7" >/dev/null
check "track: refused write is not an owner" '"deny"'    "$(dispatch m1-t03)"
check "track: refused write logged"      '1'             "$(ev '"type":"tracker.write_failed"')"
printf 'not json\n' >> "$TLOG"
check "track: corrupt log line skipped"  ''              "$(dispatch m1-t06)"

check "track: agent id mapped quietly"   ''              "$(trk PostToolUse '{"tool_name":"Agent","tool_input":{"prompt":"keel-unit: m1-t01"},"tool_response":{"status":"async_launched","agentId":"ag1"}}')"
check "track: map file written"          'm1-t01'        "$(cat "$tr_repo/.work/t2/.track/agent-ag1" 2>/dev/null)"
trk PostToolUse '{"tool_name":"Read","agent_id":"ag1","tool_input":{}}'; trk PostToolUse '{"tool_name":"Read","agent_id":"ag1","tool_input":{}}'
check "track: heartbeat throttled, tied to unit" '1'     "$(ev '"type":"heartbeat","session":"sess1234","agent":"ag1","unit":"m1-t01"')"
trk SubagentStop '{"agent_id":"ag1","agent_type":"general-purpose"}'
check "track: return mapped by agent id" '1'             "$(ev '"type":"unit.returned","session":"sess1234","agent":"ag1","unit":"m1-t01"')"
trk SubagentStop '{"agent_id":"ag9","last_assistant_message":"Done.\nkeel-unit: m1-t02"}'
check "track: return named in final message" '1'         "$(ev '"agent":"ag9","unit":"m1-t02"')"
trk SubagentStop '{"agent_id":"ag8","agent_type":"Explore"}'
check "track: untagged return"           '1'             "$(ev '"type":"agent.returned","session":"sess1234","agent":"ag8"')"
trk SubagentStop '{"agent_id":"ag5"}'
fg='{"tool_name":"Agent","tool_input":{"prompt":"keel-unit: m1-t05"},"tool_response":"Done. agentId: ag5 (internal)"}'
trk PostToolUse "$fg" >/dev/null; trk PostToolUse "$fg" >/dev/null
check "track: foreground return tied once" '1'           "$(ev '"type":"unit.returned","session":"sess1234","agent":"ag5","unit":"m1-t05"')"

check "track: stop blocked while tracker behind" 'board change' "$(trk Stop '{"stop_hook_active":false}')"
check "track: block names the unit"      'm1-t01 returned' "$(trk Stop '{"stop_hook_active":false}')"
check "track: second stop passes"        ''              "$(trk Stop '{"stop_hook_active":true}')"
synced >/dev/null
check "track: stop passes once synced"   ''              "$(trk Stop '{"stop_hook_active":false}')"

ttask prove
trk PostToolUse "$(jq -cn --arg f "$tr_repo/.work/t2/task.md" '{tool_name:"Edit", tool_input:{file_path:$f}}')"
check "track: phase change logged"       '1'             "$(ev '"data":{"phase":"prove"}')"
printf '## Counsel\nCounsel verdict: approved (round 1)\n' > "$tr_repo/.work/t2/shape.md"
w='{"tool_name":"Write","tool_input":{"file_path":"shape.md"}}'
trk PostToolUse "$w"; trk PostToolUse "$w"
check "track: counsel approval logged once" '1'          "$(ev '"type":"counsel.approved"')"

printf 'y\n' >> "$tr_repo/f"; git -C "$tr_repo" -c user.email=t@t -c user.name=t commit -qam "feat: y" -m "Keel-Unit: m1-t01"
c='{"tool_name":"Bash","tool_input":{"command":"git commit -qam y"}}'
trk PostToolUse "$c"; trk PostToolUse "$c"
check "track: commit trailer logged once" '1'            "$(ev '"type":"unit.committed","session":"sess1234","agent":"main","unit":"m1-t01"')"
printf 'z\n' >> "$tr_repo/f"; git -C "$tr_repo" -c user.email=t@t -c user.name=t commit -qam "chore: z"
trk PostToolUse '{"tool_name":"Bash","tool_input":{"command":"git -C . commit -qam z"}}'
check "track: plain commit logged"       '1'             "$(ev '"type":"commit"')"

owner m1-t07 "$FUTURE" >/dev/null
check "track: trailing period on the tag"  ''              "$(trk PreToolUse '{"tool_name":"Agent","tool_input":{"prompt":"Build the lease badge, keel-unit: m1-t07."}}')"
check "track: tag logged without the period" '1'          "$(ev '"type":"unit.dispatched","session":"sess1234","agent":"main","unit":"m1-t07"}')"
owner m1-t08 "$FUTURE" "$TURL" "" "at-8" >/dev/null; dispatch m1-t08 >/dev/null
owner m1-t08 "$FUTURE" "$TURL" "" "at-8" >/dev/null
check "track: resent owner is not a new owner" '"deny"'    "$(dispatch m1-t08)"
trk PostToolUse "$(jq -cn --arg url "$TURL" '{tool_name:"ArtifactData", tool_input:{action:"update", url:$url, collection:"tasks", doc_id:"m1-t08", data:{leaseUntil:"2099-02-01T00:00:00Z"}}, tool_response:"ok"}')" >/dev/null
check "track: lease extension is not a new owner" '"deny"' "$(dispatch m1-t08)"
owner m1-t09 "$FUTURE" "$TURL" "Updated tasks/m1-t09 (version 3): Retry refused connections" >/dev/null
check "track: 'refused' in a title is not a refusal" ''    "$(dispatch m1-t09)"
trk SubagentStop '{"agent_id":"ag6"}'
trk PostToolUse '{"tool_name":"Agent","tool_input":{"prompt":"keel-unit: m1-t07"},"tool_response":"Done. The badge shows the lease."}'
check "track: foreground return without an agent id" '1' "$(ev '"type":"unit.returned","session":"sess1234","agent":"main","unit":"m1-t07"')"
trk PostToolUse '{"tool_name":"Agent","tool_input":{"prompt":"keel-unit: m1-t09"},"tool_response":"Async agent launched successfully."}'
check "track: background launch is not a return" '0'     "$(ev '"type":"unit.returned","session":"sess1234","agent":"main","unit":"m1-t09"')"
printf '## Counsel\nRound 1: Improve\n' > "$tr_repo/.work/t2/shape.md"; trk PostToolUse "$w"
printf 'Counsel verdict: approved (round 2)\n' >> "$tr_repo/.work/t2/task.md"; trk PostToolUse "$w"
check "track: approval in task.md with a shape.md" '2'   "$(ev '"type":"counsel.approved"')"

out=$(trk SessionStart '{"source":"resume"}')
check "track: resume flags an expired lease" 'm1-t06: with a builder' "$out"
check "track: resume says the lease ran out" 'lease ran out' "$out"
check "track: resume points to claim rules" 'claim rules' "$out"
check "track: committed unit not open"   ''              "$(printf '%s' "$out" | grep -o 'm1-t01:')"

ttask build
check "track: untagged builder nudged"   'without a keel-unit' "$(trk PostToolUse '{"tool_name":"Agent","tool_input":{"prompt":"build it","model":"sonnet"},"tool_response":{"agentId":"ag7"}}')"
check "track: gate off by setting"       ''              "$(KEEL_TRACK_GATE=off dispatch m1-t10)"
before=$(wc -l < "$TLOG")
KEEL_TRACK=off trk PostToolUse '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
check "track: KEEL_TRACK=off logs nothing" "$before"     "$(wc -l < "$TLOG")"
ttask build 'tracker: none (no Artifact tool)\n'
check "track: no tracker, no gate"       ''              "$(dispatch m1-t11)"
trk StopFailure '{"error":"rate_limit: usage limit reached"}'
check "track: stop failure logged"       'usage limit'   "$(grep '"type":"session.failed"' "$TLOG")"
trk SessionEnd '{"reason":"other"}'
check "track: session end logged"        '1'             "$(ev '"type":"session.ended"')"

# A builder's own transcript (beside the session's, first line = its brief) names its unit
tx="$tmp/tx"; mkdir -p "$tx/s1/subagents"; : > "$tx/s1.jsonl"
printf '{"type":"user","message":{"role":"user","content":"Build it.\\nkeel-unit: m1-t12\\n"}}\n{"type":"assistant"}\n' > "$tx/s1/subagents/agent-ag12.jsonl"
printf '{"type":"user","message":{"role":"user","content":"Look around."}}\n{"text":"see keel-unit: m3-t02 in the skill"}\n' > "$tx/s1/subagents/agent-ag13.jsonl"
trk PostToolUse "$(jq -cn --arg t "$tx/s1.jsonl" '{tool_name:"Read", agent_id:"ag12", transcript_path:$t, tool_input:{}}')"
check "track: builder heartbeat names its unit" '1'     "$(ev '"type":"heartbeat","session":"sess1234","agent":"ag12","unit":"m1-t12"')"
trk SubagentStop "$(jq -cn --arg t "$tx/s1/subagents/agent-ag12.jsonl" '{agent_id:"ag12", agent_transcript_path:$t, last_assistant_message:"done"}')"
check "track: return found from the builder's brief" '1' "$(ev '"type":"unit.returned","session":"sess1234","agent":"ag12","unit":"m1-t12"')"
trk SubagentStop "$(jq -cn --arg t "$tx/s1/subagents/agent-ag13.jsonl" '{agent_id:"ag13", agent_transcript_path:$t, last_assistant_message:"done"}')"
check "track: tag outside the brief is ignored" '1'     "$(ev '"type":"agent.returned","session":"sess1234","agent":"ag13"')"

# Links planted in a cloned repo's .work/ are never followed
outside="$tmp/outside"; mkdir -p "$outside"; : > "$outside/rc"
mkdir -p "$tr_repo/.work/t3"; printf 't3\n' > "$tr_repo/.work/current"
printf -- '---\nsize: M\nphase: build\n---\n# goal\n' > "$tr_repo/.work/t3/task.md"
ln -s "$outside/rc" "$tr_repo/.work/t3/events.jsonl"
trk SessionStart '{"source":"startup"}' >/dev/null; trk PostToolUse '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
check "track: symlinked log not followed" ''              "$(cat "$outside/rc")"
rm "$tr_repo/.work/t3/events.jsonl"; ln -s "$outside" "$tr_repo/.work/t3/.track"
trk PostToolUse '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
check "track: symlinked state dir not followed" ''        "$(ls "$outside" | grep -v '^rc$')"
printf '../../outside\n' > "$tr_repo/.work/current"
check "track: path in the slug refused" ''               "$(trk SessionStart '{"source":"startup"}'; ls "$outside" | grep -v '^rc$')"
printf 't1\n' > "$tmp/.work/current"; rm -f "$tmp/.work/t1/gates.tsv"; ln -s "$outside/rc" "$tmp/.work/t1/gates.tsv"
printf 'it.skip("b", () => {})\n' > "$tmp/a.test.ts"; edit "$tmp/a.test.ts" >/dev/null
check "gate: symlinked gates.tsv not followed" ''         "$(cat "$outside/rc")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
