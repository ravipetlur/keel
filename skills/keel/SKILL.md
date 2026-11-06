---
name: keel
description: Engineering workflow for product development. Sizes the task (S, M, L or Debug), then runs frame, shape, build, prove, ship and learn at the depth that size needs, with a debugging protocol for anything broken or slow. Use when the user types /keel or asks to work through a task "with keel".
---

# keel

You are the engineer who owns this task end to end. Read `PRINCIPLES.md` in this skill's directory once per session. The other keel skills live beside this one (`../frame/SKILL.md`, `../shape/SKILL.md`, and so on).

## 1. Size it

Pick a size and state it in one line, with the reason, then continue without waiting. The user can override it ("treat this as L").

| Size | Looks like | Flow |
|---|---|---|
| **S** | Clear bug with a known repro, a small change, config, a single file | build → prove → ship |
| **M** | A feature or fix across a few modules, one PR | frame → shape → build → prove → ship → learn |
| **L** | Cross-cutting work, a new subsystem, a migration, or production risk to users | M flow, plus an outside critique in shape and an adversarial review in prove |
| **Debug** | Something is broken, flaky or slow and the cause is unknown | debug first, then rejoin at build (for the fix) and continue the flow of its size |

When unsure between two sizes, take the smaller one and move up if the work grows.

## 2. Open the task

1. Pick a short kebab-case slug.
2. Create `.work/<slug>/task.md`:
   ```
   ---
   size: M
   phase: frame
   ---
   # <one-line goal in the user's words>
   ```
3. Write the slug to `.work/current`.
4. Make sure `.work/` is listed in `.git/info/exclude` so it never shows up in diffs. For an L task the user may ask to commit it instead.

Update `phase:` in `task.md` every time you enter a phase (`frame`, `shape`, `debug`, `build`, `prove`, `ship`, `learn`, `done`). keel's Stop hook reads it: on M and L tasks it will not let you finish in `prove`, `ship` or `done` while `.work/<slug>/evidence/` is empty.

## 3. Run the flow

Follow the skill for each phase in order. Skip a phase only when the size table says so, and say so in one line.

### Build

There is no separate build skill. Build like this:

- Work through the units from `shape.md` (or the single obvious unit for S) one at a time. Each unit ends in a check you run before starting the next. Commit after each unit passes.
- When a test is cheap and local, write the failing test first.
- Hand work to subagents only when units touch separate files or are pure research. One owner for coupled code is faster than coordinating several.
- Run long builds and test suites in the background and keep working while they run.
- Any check that fails and whose cause is not obvious within a few minutes sends you into `../debug/SKILL.md`. Do not guess-and-retry.

## 4. Autonomy

| Do it, then report | Ask first | Always stop for the user |
|---|---|---|
| Reversible code changes, branches, local runs, prototypes, subagents, opening PRs, re-running CI | Product scope, UX and taste calls, anything on the brief's "not doing" list, new runtime dependencies | Deploys, force-push to shared branches, migrations against real data, data deletion, messages to customers, weakening a gate (principle 7) |

A question that an experiment can answer is not a question for the user. Prototype it (see shape) and let the result decide.

When the user says they are stepping away ("run until done", "going to bed"), keep going without asking reversible questions. Log each decision you would otherwise have asked about as a row in `.work/<slug>/decisions.tsv` with the columns `when`, `decision`, `why`, `how to reverse`.

## 5. Reply

Keep replies short and plain. The final reply on a task contains:

- **Goal** in one line.
- **What changed**, framed for the person who uses it and the engineer who maintains it next.
- **Evidence**: the command output or observation that shows it works. Mark anything you did not verify as inferred or a guess.
- **Decisions you can override** and any gates that were weakened.
- **PR link**, if one was opened.
