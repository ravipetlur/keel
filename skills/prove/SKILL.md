---
name: prove
description: The prove phase of the keel workflow. Runs the repo's checks, demonstrates the behavior on the real surface, self-reviews the diff, and for L tasks runs an adversarial review. Saves evidence to .work/<slug>/evidence/. Use before declaring any keel task done, or when the user asks to verify a change.
---

# Prove

Goal: evidence that the change does what the brief says, observed where users meet it. Set `phase: prove`. Save every piece of evidence under `.work/<slug>/evidence/` (command output as `.txt`, screenshots, response bodies). keel's Stop hook blocks finishing an M or L task while that folder is empty.

## 1. Repo checks

Find the repo's single verify command, in this order: `scripts/verify`, a `verify` target in the Makefile or task runner, a `verify` or `check` script in `package.json`, `pyproject.toml` or similar. If none exists, create `scripts/verify` that runs the existing typecheck, lint and test commands in sequence and exits non-zero on the first failure. Mention it in the reply.

Run it and save the output as `evidence/verify.txt`. Fix what fails. Never make it pass by weakening a check (principle 7). keel's gate hook logs any skip, suppression or ignore you add to `.work/<slug>/gates.tsv`. Each one needs a reason the user will see in the PR.

## 2. Real surface

Show the behavior from the brief's done check, on the surface where it lives:

| Surface | How |
|---|---|
| Web UI | Drive it with Playwright or the browser tools you have. Screenshot the before and after states. |
| CLI | Run the real command with realistic input. Save the output. |
| API or service | Start it and call it (`curl` or a small script). Save request and response. |
| Job, worker, webhook | Trigger it with a real or synthesized event. Save logs and the resulting state. |
| Library | Write a short example that uses the public API like a caller would. Save its output. |

If you could not reach the real surface, say exactly what you verified instead and mark the result as unverified. Never present a mock or a unit test as a live check.

## 3. Self-review the diff

Read the full diff as the next maintainer would:

- Does it meet the done check, and nothing on the "not doing" list?
- Is anything there that the requirement does not need (principle 1)?
- Are errors handled at the boundaries and nowhere else (principle 3)?
- Do comments explain only a non-obvious why? Is all debug output and instrumentation gone?
- Are tests asserting behavior a user can observe, not internals?

Fix what you find, re-run the verify command.

## 4. L only: adversarial review

Run `../review/SKILL.md` on the diff. Fix each verified finding, re-run the checks, save the review output as `evidence/review.md`.

## 5. Numbers

If the change claims a performance or cost result: a baseline and an after measurement, repeated runs, the variance, and what limits the number. Save to `evidence/bench.txt`.

Then set `phase: ship` and continue with `../ship/SKILL.md`.
