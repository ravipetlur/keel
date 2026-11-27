# Hooks

Skills are instructions the model can drift from. Hooks are scripts that run every time, so keel uses them for the rules that matter most. There are four.

## careful

**Runs:** before every Bash command, in every session, whether or not a keel task is open.

| Blocked | Asks you first |
|---|---|
| `rm -rf /`, `rm -rf ~`, `rm -rf $HOME` | `git push --force` to any branch |
| Force-push to `main` or `master` | `git reset --hard`, `git clean -f` |
| | `git branch -D`, `git checkout -- .`, `git restore .` |
| | `--no-verify` |
| | `DROP TABLE/DATABASE/SCHEMA`, `TRUNCATE TABLE` |
| | `kubectl delete`, `terraform destroy`, `helm uninstall` |

Commands like `rm -rf node_modules` or `git branch -d merged` pass through to Claude Code's normal permissions.

This is string matching. It catches the common mistakes, including ones hidden in chains like `git commit -m "x" && rm -rf /`. It is not a security boundary, and a determined command can get past it.

## gate-guard

**Runs:** after every file edit, only while a keel task is open.

It compares the edited file with the last commit and flags anything newly added that weakens a check:

- Skipped tests: `.skip(`, `xit(`, `@pytest.mark.skip`, `t.Skip(`, `@Disabled`
- Focused tests that stop the others from running: `.only(`, `fit(`
- Type-check suppressions: `@ts-ignore`, `@ts-expect-error`, `# type: ignore`
- Lint suppressions: `eslint-disable`, `# noqa`, `//nolint`, `@SuppressWarnings`

Each one is logged once to `.work/<task>/gates.tsv`, and the agent is told to give a reason or remove it. The reasons appear in the PR under **Gates weakened** for you to approve.

It doesn't block anything. Sometimes a skip is the right call, and the point is that you get to see it. Markdown and text files are ignored.

## evidence-stop

**Runs:** when the agent tries to finish, only while a keel task is open.

For an M or L task, it blocks finishing when:

- the task is in build or later and `task.md` has no `tracker:` line (`tracker: none (<reason>)` counts),
- the task is in build or later and the plan (`shape.md`, or `task.md` when there is no shape) has no `Counsel verdict: approved` line,
- the task is in prove, ship or done and `.work/<task>/evidence/` has no non-empty file.

The agent is told what's missing and how to fix it.

If the agent is only pausing to ask you something, its second attempt to stop always goes through, so this hook can never trap it in a loop. S tasks are never blocked.

## track

**Runs:** on every tool call, when a builder is dispatched or returns, and when a session starts, compacts, ends a turn, fails or ends. It is active only while a keel task is open.

It keeps the tracker current without relying on the agent to remember. Everything it sees goes to `.work/<task>/events.jsonl`, and on top of that:

| When | It does |
|---|---|
| A builder is dispatched with `keel-unit: <id>` | Refuses the dispatch unless the unit's owner was written to the tracker since its last dispatch |
| An untagged Sonnet builder is dispatched in build | Reminds the agent to tag the unit |
| The agent tries to finish a turn | Blocks while board changes (dispatches, returns, commits, phase changes, counsel approval) have not reached the tracker, and names them |
| A session starts, resumes or compacts | Tells the agent its session id, the open units with their leases, and what the tracker is missing |

The dispatch gate and the Stop check arm only after the hook has seen one write to the task's tracker, so a setup where those writes are invisible to hooks is never blocked. A second stop always goes through, as with evidence-stop. With `tracker: none`, it only logs.

The whole design is in [How keel tracks agent work](tracking.md).

## Turning them off

The hooks come with the plugin. To turn all of them off, disable the plugin with `/plugin`. gate-guard, evidence-stop and track are already quiet whenever no keel task is open. To end a task early, delete `.work/current`.

For track alone, set `KEEL_TRACK=off` (no logging at all) or `KEEL_TRACK_GATE=off` (it keeps logging but never refuses or blocks) in the `env` block of your Claude Code settings.

## Testing them

```bash
tests/hooks.test.sh
```

This feeds sample commands and edits to each hook and checks its decision. Add a case there whenever you change a pattern.

Next: [Debugging](debugging.md).
