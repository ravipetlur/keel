# Quickstart

Five minutes from install to your first task.

## 1. Install

You need `git` and `jq`. `gh` is needed to open PRs. The `codex` CLI is optional.

```bash
/plugin marketplace add ravipetlur/keel
/plugin install keel@keel
```

Restart Claude Code if the `/keel:` commands don't show up.

## 2. Give it a task

Open Claude Code in the repo you want to work on and say what you want and how you'll know it's done:

```
/keel:keel the csv export drops its last row since yesterday's deploy.
done means the 60k-row fixture exports every row.
```

You don't need to name phases or skills. A clear goal and a check that can pass or fail are enough.

## 3. What you'll see

The first line is the size and why:

> Sizing: Debug, then S. The cause is unknown, but the fix is likely in one module. Say "treat this as M" to change it.

Then it works without waiting for you. It only stops for the things listed in [Autonomy](how-it-works.md#autonomy).

As it works, a folder appears in your repo. It is hidden from git, so it never shows up in your diffs:

```
.work/
  current                  the open task
  csv-export-last-row/
    task.md                size and current phase
    debug.md               repro, hypotheses, what ruled each one out
    evidence/verify.txt    real output proving it works
```

At the end you get a short reply with the goal, what changed, the evidence, any decisions you can reverse, and the PR link.

## 4. Steer it

| You say | It does |
|---|---|
| "treat this as L" | Re-sizes and adds the critique and review steps |
| "don't change any code yet" | Stays in frame or debug and reports back |
| "going to bed, run until done" | Stops asking reversible questions and logs its decisions to `decisions.tsv` |
| "skip the PR" | Stops after prove |

## 5. Use one phase on its own

Every phase is a skill. For example:

```
/keel:debug the login test fails about 1 in 10 runs on CI
/keel:review                 # try to break the current branch's diff
/keel:frame should we add SSO for the free tier?
```

Next: [How it works](how-it-works.md).
