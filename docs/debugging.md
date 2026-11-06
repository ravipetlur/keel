# Debugging

keel treats debugging as a method, not trial and error. The rule underneath it is that every line it ships traces back to something it observed. A change that "might help" is still a guess, and guesses don't ship.

## The eight steps

| # | Step | In practice |
|---|---|---|
| 1 | **Reproduce** | Trigger it yourself where it was reported. If it won't fire, synthesize the input or add logging until it does. |
| 2 | **Observe** | Print or trace the real state while it runs. Don't infer what you can read. |
| 3 | **Hypothesize** | At least two candidate causes. Check git history in case it's a regression. |
| 4 | **Bisect** | Run the check that rules out the most candidates at once. Use `git bisect` for regressions. |
| 5 | **Attack the premise** | Two failed fixes built on the same belief means the belief is the problem. Test it directly. |
| 6 | **Fix at the root** | Fix where things first went wrong, not where the error showed up. |
| 7 | **Lock it** | A regression test that fails before the fix and passes after. Remove the temporary logging. |
| 8 | **Verify** | The original repro now passes, on the same surface. "Inconclusive" counts as a fail. |

Progress is kept in `.work/<task>/debug.md`, so you can see which hypotheses were ruled out and why.

## By problem type

**Slow.** Measure a baseline before touching anything. Profile instead of guessing. Change one thing at a time. Report before and after numbers along with what limits them.

**Flaky.** Run it about 50 times to get a failure rate. Look for shared state, test order, clocks and network. Retrying or raising a timeout isn't a fix, and gate-guard will flag a skip.

**Production incident.** Read logs, metrics and recent deploys first, and change nothing. Propose a rollback or flag-off to you before touching production. Find the root cause once things are stable.

## Example

```
/keel:debug users get two notifications after a retry
```

> **Repro:** `scripts/retry-sim.ts --fail-once` sends 2 emails (expected 1).
> **Hypotheses:** (a) the retry re-enqueues without a dedupe key; (b) the worker acks after sending, so a crash re-delivers.
> **Ruled out (b):** the worker log shows one delivery per message ID.
> **Root cause:** `enqueue()` builds a new idempotency key on each attempt.
> **Fix:** derive the key from the notification ID. A regression test was committed before the fix.
> **Verified:** `retry-sim --fail-once` now sends 1 email. Output is in `evidence/verify.txt`.

The example above is illustrative.
