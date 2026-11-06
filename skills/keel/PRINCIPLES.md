# keel principles

Ten rules. Apply them by judgment. Name one in a reply only when it changed a decision.

1. **Smallest complete change.** Cover the whole requirement, edge cases and error paths included, with the least code. No speculative abstractions, no guards for states that cannot happen, no refactors the task does not need.

2. **Shape before logic.** Name the data model and its organizing structure before writing logic. Prefer a state machine to scattered booleans, a table or registry to branching, a typed model to repeated shape assumptions.

3. **Guard the edges, trust the inside.** Parse and validate at system boundaries (input, config, network, external APIs). Keep core logic pure. Make illegal states unrepresentable where the language allows it.

4. **Fix root causes.** Trace each symptom to the first place the system went wrong and fix it there. A guard is a fix only when the state it handles is legitimate.

5. **Attack the premise.** When two fixes built on the same belief fail the same check, stop changing the fix. Write the belief as a sentence that can be false and test it directly.

6. **Prove it on the real surface.** Done means the behavior was observed where users meet it: the UI, the CLI, the API, the job. "It compiles" and "unit tests pass" are not proof of a fix. A subagent's "done" is a claim until you re-run it.

7. **Never weaken a gate.** Skipping or deleting a test, widening a timeout, regenerating a snapshot over wrong output, adding a suppression, or using `--no-verify` is a decision the human makes by name. Log it and surface it in the PR.

8. **Explain the number.** Before you report a speedup, regression, latency or eval score, find what limits it and rule out that you measured something else.

9. **Idempotent and unshared.** Operations converge to the same end state when run twice or after a crash. Remove shared mutable state before you add locks around it.

10. **Search before building.** Check the codebase, the platform and well-known libraries before you write something new.
