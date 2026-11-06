---
name: ship
description: The ship phase of the keel workflow. Turns verified work into small ordered commits and a PR with the why, the evidence and the decisions the user can override, then watches CI to green. Deploys only with explicit user approval. Use when a keel task has passed prove, or when the user asks to open a PR for verified work.
---

# Ship

Goal: a PR a reviewer can trust in two minutes. Set `phase: ship`.

## 1. Commits

- Work on a branch, never directly on the default branch.
- Rebase into small commits in the order of the units in `shape.md`. Each commit builds and passes its own check.
- For bug fixes, the commit that adds the failing regression test comes before the commit with the fix, when that was cheap to do.
- Conventional commit messages (`feat:`, `fix:`, `refactor:` and so on). Follow the repo's own convention if it has one.

## 2. Pull request

Write the body from `PR.md` in this skill's directory, using the brief and the evidence folder:

- **Why** comes from the brief: the user and the problem.
- **Evidence** pastes the key lines of the real output, not "tests pass".
- **Gates weakened** lists every row in `.work/<slug>/gates.tsv` with its reason. If there are none, write "None".
- **Decisions you can override** comes from `decisions.tsv` and the forks in `shape.md`.

Open it with `gh pr create`, using the repo's PR template if it has one and filling the sections above into it.

## 3. CI

Watch the checks (`gh pr checks --watch` in the background). When one fails:

- A real failure goes through `../debug/SKILL.md`, then back through prove.
- A suspected flake gets one re-run. If it fails again, treat it as a real failure.

Address review comments on their merits. Push back with a concrete reason when a comment is wrong.

## 4. Deploy

Never deploy, merge to a protected branch, or run production migrations without the user saying so in this session. When the user does, watch errors, logs and the key metric for the changed path for a few minutes afterwards and report what you saw.

Then continue with `../learn/SKILL.md`.
