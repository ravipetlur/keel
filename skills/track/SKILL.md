---
name: track
description: Keeps a live, pinned tracker page for a keel task. It is a claude.ai Artifact backed by its own database: an agent console with the project clock, flow metrics, what each agent (planner, counsel, executor) is doing, and a kanban board whose cards are colored by whether the owner must act. Opened with every M and L keel task and updated at every state change. Use when a keel task opens, when the user asks for progress, a dashboard or a tracker, or after any task state change while one is open.
---

# Track

The person who asked for the work follows it on one page they never have to look for: a tracker pinned to their claude.ai sidebar. A tracker that falls behind is worse than none. The responsible party (Opus, see `../keel/SKILL.md`) owns the tracker; builders and the counsel never write to it.

You don't have to remember when to update it. keel's `track` hook records every dispatch, return, commit, phase change and session event in `.work/<slug>/events.jsonl` as it happens (see `docs/tracking.md` in the plugin). It refuses to dispatch a unit whose owner isn't in the tracker yet. It blocks your Stop while the tracker is behind, and it names what's missing. When a `[keel track]` note says the tracker is behind, sync it before anything else.

**When.** Every M and L task gets one, opened right after `task.md` is written. S and Debug-then-S tasks get one only if the user asks. If the Artifact tool is not available in this session, write `tracker: none (<reason>)` into `task.md`, say so once in the reply, and carry on.

## 1. Open it

1. Copy `template.html` (next to this file) to the session scratchpad as `<slug>-tracker.html` and set its `<title>` to `<Goal in 2-4 words> Tracker`. Everything else on the page comes from its database.
2. Load the `artifact-design` and `artifact-capabilities` skills before publishing. The template already follows the page contract.
3. Publish with `icon: "chart"`, a one-sentence `description`, `pin: true`, and the `db` capability (viewers read, only the owner writes; take the exact rule syntax from `artifact-capabilities`). Republish the same file path later to keep the URL.
4. Add `tracker: <url>` to the frontmatter of `.work/<slug>/task.md`. Later sessions on the same task update that page, never a new one.
5. Seed the database with one `ArtifactData` batch (shapes in section 2): `project/info` with `roles`, one milestone per phase of the task's flow with planned dates, `status/current` (with `session`), `status/activity`, `status/usage` if a budget is known, and any `asks`. This first write is what arms the hook's dispatch gate and Stop check for the task.

**What the page shows.** A dark agent console laid out as a kanban board, with no sprints. The page reads the role from `who`: Opus is shown as **Planner**, Fable as **Counsel**, Sonnet as **Executor**. Lanes come from each task row:

| Lane | Rows |
|---|---|
| Backlog | `status: queued` |
| Plan + counsel | not done, `milestone` Frame, Shape or Debug |
| Build | Build rows that are `building`, `fixing` or `waiting` |
| Review + prove | `status: review`, or not done with `milestone` Prove, Ship or Learn |
| Done | `status: done` (the six most recent are shown) |

Card color says whether the owner must act: `waiting` is amber (**needs your decision**), or red (**blocked on you**) when `need: "blocked"`; `review` is blue (agent reviewing); `building` and `fixing` are neutral with a pulse (agent working); `queued` is dashed. A running card whose `leaseUntil` has passed turns dashed gray (**no signal**); the page works that out itself every minute, so it is never written. The header warns when `status/current.updatedAt` is over 30 minutes old while units are running. Every `waiting` row, and every ask with `status: now`, also shows in the Needs you panel, oldest `waitingSince` first. Opened outside claude.ai, the page shows labeled example data.

## 2. Data model (exact field names; the page depends on them)

| Document | Fields |
|---|---|
| `project/info` | `name`, `targetLabel` (e.g. "PR"), `plannedStart`, `plannedEnd`, `expectedEnd`, `baselineNote` (one sentence: what "planned" means), `roles` (see below), optional `wip` (`{plan, build, review}` lane limits; defaults 3, 4, 4) |
| `status/usage` | optional: `spendUsd`, `budgetUsd`, `byRole: {planner, counsel, executor}` each `{tokens, costUsd}`, `days: [{day, planner, counsel, executor}]` (tokens per role per UTC day, about 14 kept) |
| `status/current` | `phase` ("Build"), `headline` (plain words: what is happening now), `milestoneEta`, `askNow` (only while the user must act; it shows as the NEEDS YOU box), `updatedAt`, `session` (this session's id from the `[keel track]` note, so a later session can tell who last synced) |
| `status/activity` | `entries: [{at, text}]`, newest first, about 14 kept |
| `milestones/m<N>` | `order`, `code` (the phase name: "Frame", "Shape", "Build", "Prove", "Ship", "Learn"), `title` (what the phase delivers, e.g. "Plan approved", "Units built and reviewed"; never the phase name again), `summary`, `status` (`done` / `active` / `planned` / `later`), `plannedStart`, `plannedEnd`, `actualStart`, `actualEnd`, `expectedEnd` |
| `tasks/m<N>-t<NN>` | `order` (N×100 + number), `milestone` (the phase code), `number` (0 is the plan row: shown, not counted), `title`, `note` (what it delivers), `who`, `status` (`queued` / `building` / `review` / `fixing` / `waiting` / `done`, nothing else), `plannedAt`, `startedAt`, `closedAt`, `expectedAt`, `expectedNote`, `reviewRounds`; optional: `checks` (`{passed, failed, total}` from the unit's last check run), `tokens`; while `waiting`: `need` (`decision` or `blocked`), `question` (one or two plain sentences: what keel needs and why), `options` (short answer labels), `waitingSince`; while a builder has it: `assignee` (`{session, agent, model}`, e.g. `{session: "3f9a2c1b", agent: "builder", model: "Sonnet 5.5"}`), `assignedBy` (`push` / `pull`), `assignedAt`, `leaseUntil`, `attempt` (1, plus 1 for each re-assignment after a lease ran out) |
| `assignments/<task id>-a<N>` | one per assignment, the history: `unit`, `attempt`, `to` (the assignee), `how` (`push` / `pull`), `startedAt`, `endedAt`, `outcome` (`done` / `released` / `expired` / `reclaimed`) |
| `asks/a<N>` | `order`, `status` (`now` / `later` / `done`), `when`, `text` |

`roles` is the three rows from the roles table in `../keel/SKILL.md`, each `{role, model, does}`: Responsible / Opus 5.5 / owns the plan, reviews every unit, proves and ships; Counsel / Fable 5.2 / reviews every plan, approves or improves it; Builder / Sonnet 5.5 / implements each unit.

`who` names the role that has the row: "Sonnet" for build units, "Fable" for plan reviews, "Opus" for prove and ship rows, "You" when it waits on the user.

Times are UTC ISO strings from `date -u +%FT%TZ`. A `planned*` field is set once, when Fable approves the plan, and never moved. Re-forecasts go only into `expected*` fields.

## 3. What goes where

| Phase | Rows |
|---|---|
| Frame | "Brief" (Opus), and for L "Counsel review of the brief" (Fable) |
| Shape | t00 "Plan and counsel review" (Fable, `reviewRounds` = counsel rounds), then any forks settled by prototype (Opus) |
| Debug | "Reproduce and find the cause" (Opus); the fix plan's counsel review (Fable) |
| Build | One row per unit in `shape.md`, `who: "Sonnet"`, `reviewRounds` = Opus review rounds on that unit |
| Prove | "Repo checks", "Real-surface check", and for L "Adversarial review" (all Opus) |
| Ship | "PR open", "CI green" (Opus) |
| Learn | "Lessons recorded" (Opus) |

## 4. Update at every state change (one batch per change, read first, pass `if_version`)

| When | Writes |
|---|---|
| Phase entered | its milestone `active` with `actualStart`; the previous one `done` with `actualEnd` |
| Counsel verdict | the review row `done` or `fixing` (`reviewRounds` + 1); an activity line with the verdict in plain words |
| Plan approved | every Build row with `plannedAt`; milestone planned dates; `milestoneEta` |
| **Before** a unit goes to a builder (the hook refuses the dispatch otherwise) | one inline `data` update to `tasks/<id>`: `status: building`, `startedAt`, `expectedAt`, `assignee`, `assignedBy: "push"`, `assignedAt`, `leaseUntil` (the unit's expected duration plus 30 minutes, or 90 minutes with no estimate), `attempt`; and a new `assignments/<id>-a<N>` row. Then dispatch with `keel-unit: <id>` in the brief |
| Unit back for Opus review | `status: review` |
| Opus sends it back | `status: fixing`, `reviewRounds` + 1, and the owner again (`assignee` with a new `assignedAt` and `leaseUntil`) before the re-dispatch |
| Builder died without a result | record the owner again (new `assignedAt` and `leaseUntil`, same `attempt`) and re-dispatch |
| Unit accepted and committed (with a `Keel-Unit: <id>` trailer) | `status: done`, `closedAt` (exact `date -u`), the `assignments` row `outcome: done` with `endedAt`; activity line; re-forecast later `expectedAt` and `expectedEnd` if the pace changed |
| Each sync while units run | extend `leaseUntil` on running units that are still on pace; write only `leaseUntil`, because a new `assignedAt` is what marks a new assignment |
| Unit check run | `checks` with the real counts |
| User needed | the row `waiting` with `need`, `question`, `options`, `waitingSince`; an ask `now`; `askNow` (after the answer: the row back to its working status, clear `need`, `question`, `options`, `askNow`, mark the ask `done`) |
| Usage known (end of each phase, at least) | `status/usage` totals and today's `days` entry |
| PR opened, task closed | the Ship and Learn rows; the PR link in an activity line; `project/info.expectedEnd` set to the actual end |
| Every change | `status/current.headline`, `milestoneEta`, `updatedAt`, `session` |

Use plain words that name what the user sees. No commit hashes, file paths or internal ids in notes.

Write the owner inline in `data`, not through `file_path`, so the hook can see it. The hook counts a write as a new owner only when it carries `assignee` and an `assignedAt` it hasn't seen for that unit. Any write to the tracker counts as a sync for the Stop check, so put everything the hook listed into one batch.

## 5. Claims (pull, when the owner is gone)

Push is the default. Pull is for when the session that handed out a unit is gone: it hit a usage limit or closed. At session start the hook lists units in this checkout whose lease ran out. Units leased elsewhere show only in the tracker, so read `tasks/` there too.

Claim a task only when all of these hold:

- its status is `building`, `fixing` or `review`,
- its `leaseUntil` has passed,
- its owner is quiet: `status/current.updatedAt` is over 30 minutes old, or this checkout's log shows the owner's session ended,
- its `attempt` is below 2.

If this session was the owner, record the owner again and carry on (`attempt` + 1). Otherwise claim it with one batch, pinning `if_version` to the version you just read: the task's `assignee` (you), `assignedBy: "pull"`, `assignedAt`, a new `leaseUntil`, `attempt` + 1; the old `assignments` row `outcome: expired`, `endedAt`; a new `assignments` row. If the write is refused because the version moved, another session claimed it first: re-read and leave it. Then read the task back, and dispatch only if `assignee.session` is yours. Add an activity line: "Picked up <title> after the previous session went quiet."

When a lease runs out at `attempt` 2, don't claim it. Set `status: waiting`, `need: "blocked"`, a `question` saying the unit stalled twice and what you saw, and an ask `now`.

## 6. Checks

- Before every reply to the user while a task is open: is the tracker current? If not, update it first. The Stop hook checks this for you and names what is missing.
- When the user says the tracker is wrong: fix the data at once, then add a line to `.work/learnings.md`.
- Status strings are exactly those in section 2. The page knows no synonyms.
