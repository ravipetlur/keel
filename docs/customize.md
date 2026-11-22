# Customize

keel is a small set of Markdown files and shell scripts. Changing it means editing those files.

## Where things live

| Want to change | Edit |
|---|---|
| The principles | `skills/keel/PRINCIPLES.md` |
| Sizes, the flow, roles and models, autonomy rules, reply format | `skills/keel/SKILL.md` |
| The tracker page or its data | `skills/track/SKILL.md`, `skills/track/template.html` |
| One phase | `skills/<phase>/SKILL.md` |
| The brief, shape or PR layout | `skills/frame/brief.md`, `skills/shape/shape.md`, `skills/ship/PR.md` |
| What gets blocked or asked about | `hooks/careful.sh` |
| What counts as weakening a gate | the `patterns` list in `hooks/gate-guard.sh` |

After an edit, run `/plugin` and update keel, or reinstall it, so Claude Code picks up the change.

## Rules for changing keel

1. **Keep skills short.** Strong models don't need step-by-step instructions. Say the goal, the bar for done, and the hard limits.
2. **Turn repeated mistakes into code, not more words.** If you keep adding the same instruction, write a hook, lint or test instead.
3. **Prove a change helps.** Run the same few real tasks with and without the change. Keep it only if the results get better.
4. **Test hook changes.** Add a case to `tests/hooks.test.sh` and run it.

## Common tweaks

**Make S tasks lighter or heavier.** Edit the S row of the size table in `skills/keel/SKILL.md`.

**Commit the `.work/` files on big tasks.** Step 4 of "Open the task" in `skills/keel/SKILL.md` already allows this for L. Widen it if you want.

**Share lessons with your team.** Move `.work/learnings.md` to a committed path such as `docs/learnings.md`, and update `skills/learn/SKILL.md` to match.

**Change which model plays which role.** Edit the roles table in section 0 of `skills/keel/SKILL.md`. The `Agent model` column is what keel passes when it starts a subagent (`sonnet`, `fable`, `opus`). Update the `roles` line in `skills/track/SKILL.md` and the Roles block in `skills/ship/PR.md` to match.

**Use a different second model for review.** `review` tries the `codex` CLI first, then a subagent on a different model, then fresh subagents. Reorder that list to suit what you have.

**Track S tasks too.** Change the "When" line in `skills/track/SKILL.md`.
