---
name: learn
description: The learn phase of the keel workflow. Records what the task taught in one line each, and turns any lesson seen for the second time into a lint, hook, test or script instead of more text. Closes the keel task. Use at the end of every keel task, or when the user says the agent keeps making the same mistake.
---

# Learn

Goal: the next task is faster and makes fewer mistakes. Two minutes, no ceremony. Set `phase: learn`.

## 1. Record

Add one line per real lesson to `.work/learnings.md` in the form `YYYY-MM-DD | <lesson> | <evidence or task slug>`. A lesson is something that cost time and would cost time again: a project quirk, a wrong assumption, a command that behaves unexpectedly. Skip the obvious.

Lessons about how this repository works that every future session needs (how to run the app, a non-obvious convention) go into the project's `CLAUDE.md` as one line instead.

## 2. Promote to structure

Search `.work/learnings.md` for an earlier line saying the same thing. If the lesson has now come up twice, do not write it a third time. Encode it at the highest level that works:

1. Make the mistake impossible: a type, an API shape, a config default.
2. Catch it automatically: a lint rule, a CI check, a hook, a test.
3. Make the right way the easy way: a script or `make` target.
4. Only if none of these fit, a line in `CLAUDE.md`.

Ship the structural fix as its own small commit or PR, and mark the learning lines as `-> encoded in <file>`.

## 3. Close the task

Set `phase: done` in `task.md`, then delete `.work/current`. Give the final reply described in `../keel/SKILL.md`.
