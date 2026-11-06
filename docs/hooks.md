# Hooks

Skills are instructions the model can drift from. Hooks are scripts that run every time, so keel uses them for the rules that matter most. There are three.

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

For an M or L task in the prove, ship or done phase, it blocks finishing while `.work/<task>/evidence/` has no non-empty file. The agent is told to save the verify output and the real-surface check first.

If the agent is only pausing to ask you something, its second attempt to stop always goes through, so this hook can never trap it in a loop. S tasks are never blocked.

## Turning them off

The hooks come with the plugin. To turn all of them off, disable the plugin with `/plugin`. gate-guard and evidence-stop are already quiet whenever no keel task is open. To end a task early, delete `.work/current`.

## Testing them

```bash
tests/hooks.test.sh
```

This feeds sample commands and edits to each hook and checks its decision. Add a case there whenever you change a pattern.

Next: [Debugging](debugging.md).
