---
name: keel
description: Engineering workflow for product development. Sizes the task (S, M, L or Debug), then runs frame, shape, build, prove, ship and learn at the depth that size needs, with a debugging protocol for anything broken or slow. Sonnet 5.5 builds, Fable 5.2 approves every plan, Opus 5.5 is responsible for the result, and M and L tasks get a pinned live tracker. Use when the user types /keel or asks to work through a task "with keel".
---

# keel

You are the engineer who owns this task end to end. Read `PRINCIPLES.md` in this skill's directory once per session. The other keel skills live beside this one (`../frame/SKILL.md`, `../shape/SKILL.md`, and so on).

## 0. Roles

Every keel task, at every size, runs with three roles on three models:

| Role | Model | Agent `model` | Does | Never does |
|---|---|---|---|---|
| **Responsible** | Opus 5.5 (`claude-opus-5-5`) | `opus` | Runs this session. Sizes, frames, shapes and debugs. Dispatches every unit, reviews what comes back, re-runs its check, commits it. Runs prove, ships, keeps the tracker. Accountable for the result. | Write the production code for a unit |
| **Counsel** | Fable 5.2 (`claude-fable-5-2`) | `fable` | Reviews every plan before build starts and returns **Approved** or **Improve** with concrete changes. | Write code, or approve its own suggestions |
| **Builder** | Sonnet 5.5 (`claude-sonnet-5-5`) | `sonnet` | Implements one unit at a time from the approved plan, runs the unit's check, reports the output. | Change the plan, widen scope, or weaken a gate |

If this session is not running on Opus 5.5, say so in the sizing line and ask the user to switch (`/model opus`). Until they do, send each Opus checkpoint (unit acceptance, prove sign-off) to an `opus` subagent and act on its verdict.

**Counsel loop.** Give a fresh `fable` subagent the plan (`brief.md` and `shape.md`, or the `## Plan` in `task.md` when there is no shape), the relevant file paths, and this brief:

> You are counsel on this plan. Read the code it touches. Answer **Approved**, or **Improve** with each change as: what to change, why, and the code that shows it. Look for what will break, what is missing, and what is over-built. Do not rewrite the plan and do not write code.

Apply each improvement, or reject it with a one-line reason, then send the revised plan back. Build starts only on **Approved**. After two rounds without approval, take the open points to the user. Record each round in the plan's `Counsel` section, ending in the line `Counsel verdict: approved (round N)`.

**Builder brief.** Give each `sonnet` subagent the unit, its check, the approved plan, the files it may touch, and principles 1, 3 and 7. It returns the diff summary and the check's real output. Its "done" is a claim (principle 6): you read the diff, re-run the check, and either commit it or send it back with what to fix.

## 1. Size it

Pick a size and state it in one line, with the reason, then continue without waiting. The user can override it ("treat this as L").

| Size | Looks like | Flow |
|---|---|---|
| **S** | Clear bug with a known repro, a small change, config, a single file | plan → build → prove → ship |
| **M** | A feature or fix across a few modules, one PR | frame → shape → build → prove → ship → learn |
| **L** | Cross-cutting work, a new subsystem, a migration, or production risk to users | M flow, plus counsel on the brief before shape and an adversarial review in prove |
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
5. For M and L, open the tracker with `../track/SKILL.md`: a pinned claude.ai page the user follows the task on. Its URL goes into `task.md` as `tracker:`. Update it at every state change from here to `done`.

Update `phase:` in `task.md` every time you enter a phase (`frame`, `shape`, `debug`, `build`, `prove`, `ship`, `learn`, `done`), and the tracker with it. keel's Stop hook reads it. On M and L tasks it will not let you finish in `build` or later without a `tracker:` line and a counsel approval (in `shape.md`, or in `task.md` when there is no shape), or in `prove`, `ship` or `done` while `.work/<slug>/evidence/` is empty.

## 3. Run the flow

Follow the skill for each phase in order. Skip a phase only when the size table says so, and say so in one line.

### Plan in task.md

S tasks, and any task that rejoins at build from debug without a `shape.md`, write the plan into `task.md` under `## Plan` before building: the change in two or three lines, the files, and the check. Run the counsel loop on it and record the rounds under `## Counsel` in `task.md`.

### Build

There is no separate build skill. Build like this:

- Work through the units from `shape.md` (or the single unit in the S plan) one at a time. Each unit goes to a builder (section 0) and ends in a check. You review the diff, re-run the check, and commit before starting the next.
- When a test is cheap and local, the builder writes the failing test first.
- Units that touch the same files go to one builder in order. Run builders in parallel only on units with no files in common.
- Run long builds and test suites in the background and keep working while they run.
- Any check that fails and whose cause is not obvious within a few minutes sends you into `../debug/SKILL.md`. You investigate; the fix goes back to a builder as a unit. Do not guess-and-retry.
- If the build shows the plan was wrong, revise the plan and run it past counsel again before continuing.

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
- **PR link**, if one was opened, and the **tracker** link.
