---
name: track
description: Keeps a live, pinned tracker page for a keel task. It is a claude.ai Artifact backed by its own database, showing plan against actual per phase, the units of work with who built and reviewed each, what the owner needs to do, and recent activity. Opened with every M and L keel task and updated at every state change. Use when a keel task opens, when the user asks for progress, a dashboard or a tracker, or after any task state change while one is open.
---

# Track

The person who asked for the work follows it on one page they never have to look for: a tracker pinned to their claude.ai sidebar. A tracker that falls behind is worse than none, so update it in the same turn as every change it shows. The responsible party (Opus, see `../keel/SKILL.md`) owns the tracker; builders and the counsel never write to it.

**When.** Every M and L task gets one, opened right after `task.md` is written. S and Debug-then-S tasks get one only if the user asks. If the Artifact tool is not available in this session, write `tracker: none (<reason>)` into `task.md`, say so once in the reply, and carry on.

## 1. Open it

1. Copy `template.html` (next to this file) to the session scratchpad as `<slug>-tracker.html` and set its `<title>` to `<Goal in 2-4 words> Tracker`. Everything else on the page comes from its database.
2. Load the `artifact-design` and `artifact-capabilities` skills before publishing. The template already follows the page contract.
3. Publish with `icon: "chart"`, a one-sentence `description`, `pin: true`, and the `db` capability (viewers read, only the owner writes; take the exact rule syntax from `artifact-capabilities`). Republish the same file path later to keep the URL.
4. Add `tracker: <url>` to the frontmatter of `.work/<slug>/task.md`. Later sessions on the same task update that page, never a new one.
5. Seed the database with one `ArtifactData` batch (shapes in section 2): `project/info` with `roles`, one milestone per phase of the task's flow with planned dates, `status/current`, `status/activity`, and any `asks`.

## 2. Data model (exact field names; the page depends on them)

| Document | Fields |
|---|---|
| `project/info` | `name`, `targetLabel` (e.g. "PR"), `plannedStart`, `plannedEnd`, `expectedEnd`, `baselineNote` (one sentence: what "planned" means), `roles` (see below) |
| `status/current` | `phase` ("Build"), `headline` (plain words: what is happening now), `milestoneEta`, `askNow` (only while the user must act; it shows as the NEEDS YOU box), `updatedAt` |
| `status/activity` | `entries: [{at, text}]`, newest first, about 14 kept |
| `milestones/m<N>` | `order`, `code` (the phase name: "Frame", "Shape", "Build", "Prove", "Ship", "Learn"), `title` (what the phase delivers, e.g. "Plan approved", "Units built and reviewed"; never the phase name again), `summary`, `status` (`done` / `active` / `planned` / `later`), `plannedStart`, `plannedEnd`, `actualStart`, `actualEnd`, `expectedEnd` |
| `tasks/m<N>-t<NN>` | `order` (N×100 + number), `milestone` (the phase code), `number` (0 is the plan row: shown, not counted), `title`, `note` (what it delivers), `who`, `status` (`queued` / `building` / `review` / `fixing` / `waiting` / `done`, nothing else), `plannedAt`, `startedAt`, `closedAt`, `expectedAt`, `expectedNote`, `reviewRounds` |
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
| Unit dispatched to a builder | `status: building`, `startedAt`, `expectedAt` |
| Unit back for Opus review | `status: review` |
| Opus sends it back | `status: fixing`, `reviewRounds` + 1 |
| Unit accepted and committed | `status: done`, `closedAt` (exact `date -u`); activity line; re-forecast later `expectedAt` and `expectedEnd` if the pace changed |
| User needed | the row `waiting`; an ask `now`; `askNow` (clear it after, mark the ask `done`) |
| PR opened, task closed | the Ship and Learn rows; the PR link in an activity line; `project/info.expectedEnd` set to the actual end |
| Every change | `status/current.headline`, `milestoneEta`, `updatedAt` |

Use plain words that name what the user sees. No commit hashes, file paths or internal ids in notes.

## 5. Checks

- Before every reply to the user while a task is open: is the tracker current? If not, update it first.
- When the user says the tracker is wrong: fix the data at once, then add a line to `.work/learnings.md`.
- Status strings are exactly those in section 2. The page knows no synonyms.
