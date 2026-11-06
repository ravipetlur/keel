---
name: review
description: Adversarial code review. Independent reviewers try to break a change, and only findings proven by running something survive. Reports findings without fixing them unless asked. Use for /review, "try to break this", "adversarial review", or as the prove step of an L keel task.
---

# Review

Goal: find what is actually broken in a change, with proof, and nothing else.

## 1. Scope and intent

The scope is what the user names. Otherwise it is the diff from the merge base with the default branch to the working tree. State the intent of the change in two sentences from the brief, the commits or the PR description.

## 2. Reviewers

Use two independent reviewers. Prefer different models so they fail differently:

- `codex exec` with the brief below, if the `codex` CLI is installed.
- A subagent on a different model from the one you are running on.
- If neither is available, two fresh subagents.

Give each reviewer the scope, the intent, the relevant file paths, and this brief:

> Break this change. For every finding, prove it by running something against the real code: a failing test, a repro script, or command output that shows the wrong behavior. Work in a scratch copy or worktree and do not modify the main checkout. Report each finding as: title, the exact command, the output it printed, and the output the intent requires. Leave out anything you did not run, including style, naming and hypothetical future risks. No findings is a valid answer.

## 3. Verify

Re-run each finding's command yourself. Keep it only if the output shows the failure and the failure contradicts the intent. Merge findings with the same root cause.

## 4. Report

- **Intent.** The two sentences.
- **Verified findings.** For each: command, output, why it breaks the intent, which reviewer found it.
- **Dropped.** Per reviewer, how many findings were dropped and why, in one line.

Do not fix anything unless the user asked for fixes or this review runs inside a keel task, where prove fixes the verified findings.
