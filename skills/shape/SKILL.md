---
name: shape
description: The shape phase of the keel workflow. Settles the data model, interfaces, ordered units of work, top risks and open design forks in about one screen, settling forks with quick prototypes instead of questions. Use for M and L keel tasks, or when the user asks for a lightweight design or plan before coding.
---

# Shape

Goal: just enough design that the build is obvious and reviewable. This is not a spec. If `shape.md` grows past one screen, the task is probably L or should be split.

## Do

1. Read the code you are about to change and its callers. Note existing patterns you should follow.
2. Write `.work/<slug>/shape.md` from `shape.md` in this skill's directory:
   - **Data model and interfaces.** Types, state machine, API and function signatures, written from the caller's side (principle 2).
   - **Units of work.** An ordered list. Each unit leaves the system working and ends in a check you can run. This order becomes the commit order and, for large work, the PR stack.
   - **Risks.** The top three, each with how you will detect it.
   - **Forks.** Design choices still open.
3. **Settle forks by experiment.** If a fork is about behavior, performance, layout or feasibility, build a throwaway prototype (15 to 30 minutes, outside the main change, deleted afterwards) and let the result decide. Record the decision and the evidence in one line. Only product or taste forks go to the user.
4. **L only: outside critique.** Get one critique of `shape.md` from a reviewer that did not write it. Use the first that is available:
   - `codex exec` with the brief and shape, if the `codex` CLI is installed.
   - A subagent on a different model from the one you are running on.
   - A fresh subagent given only the brief, the shape and the relevant file paths.
   Ask it: "What will break, what is missing, and what is over-built? Cite the code." Accept or reject each point with a one-line reason in `shape.md`. One round only.

Then set `phase: build` and build as described in `../keel/SKILL.md`.
