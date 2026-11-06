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
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
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
task() { printf -- '---\nsize: %s\nphase: %s\n---\n# goal\n' "$1" "$2" > "$tmp/.work/t1/task.md"; }

task M build;  check "stop: M build passes"     ''         "$(stop)"
task M prove;  check "stop: M prove no evidence" '"block"' "$(stop)"
               check "stop: second stop passes" ''         "$(stop true)"
task S done;   check "stop: S never blocks"     ''         "$(stop)"
task L ship;   mkdir -p "$tmp/.work/t1/evidence"; : > "$tmp/.work/t1/evidence/empty.txt"
               check "stop: empty file is not evidence" '"block"' "$(stop)"
printf 'ok\n' > "$tmp/.work/t1/evidence/verify.txt"
               check "stop: L ship with evidence" ''       "$(stop)"
rm "$tmp/.work/current"
task M prove;  rm -rf "$tmp/.work/t1/evidence"
               check "stop: no open task passes" ''        "$(stop)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
