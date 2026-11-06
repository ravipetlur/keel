---
name: debug
description: Evidence-driven debugging protocol. Reproduce, observe, list hypotheses, bisect, attack the premise after two failed fixes, fix at the root, lock it with a regression test, and verify on the same surface. Includes variants for performance problems, flaky tests and production incidents. Use whenever something is broken, failing, flaky or slow and the cause is not already known.
---

# Debug

Goal: find the actual cause, fix it there, and prove it. Every line you ship traces to something you observed. A change that "might help" is a hypothesis. It does not ship.

If a keel task is open, set `phase: debug` and keep a running log in `.work/<slug>/debug.md`: the repro, each hypothesis, the observation that confirmed or ruled it out.

## Protocol

1. **Reproduce** it yourself on the surface where it was reported: the UI, CLI, API or job. If it will not trigger, make it: synthesize the input, tighten timing, scale the data, or add instrumentation until it fires. Ask the user only after that, with a specific reason you cannot reach it.
2. **Observe.** Add logging, tracing or a debugger and read the actual state while it runs. Do not infer state you can print.
3. **Hypothesize.** List at least two candidate causes. Check whether it is a regression: `git log` and `git blame` on the area, and the last known good version.
4. **Bisect.** Choose the observation that rules out the most candidates at once and run it. Repeat until one cause survives. For a regression with a known good commit, use `git bisect run` with a script.
5. **Attack the premise.** If two fixes built on the same belief have failed, stop. Write the belief down as a sentence that can be false, test it directly, and only then try another fix.
6. **Fix at the root.** Change the first place the system went wrong, not where the symptom surfaced. Revert any change motivated by a hypothesis that was ruled out.
7. **Lock it.** Add a regression test that fails before the fix and passes after. Commit the failing test before the fix when it is cheap to do so. Remove the temporary instrumentation.
8. **Verify** on the same surface as step 1. The original repro now passes. "Inconclusive" or a check on a different surface is a fail.

Write the outcome into the reply: symptom, root cause, fix, and the failing-then-passing output.

## Variants

**Performance.** Measure a baseline first, on realistic data, several runs. Profile instead of guessing (CPU profile, flame graph, query plan, network waterfall). Change one thing at a time and re-measure. Report before and after with what limits the number (principle 8).

**Flaky test.** Run it many times (for example 50) to get a failure rate before and after. Look for shared state, ordering, real time and clocks, network, and resource leaks between tests. Never fix flakiness by retrying or by widening a timeout alone. That is weakening a gate.

**Production incident.** Read first, change nothing: logs, metrics, error tracker, recent deploys and config changes. Establish the timeline and blast radius. Propose the mitigation (rollback, flag off) to the user before any write to production. Root-cause after the bleeding stops.

When the cause is known, return to the flow: set `phase: build` for the fix, then prove.
