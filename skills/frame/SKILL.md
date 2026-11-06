---
name: frame
description: The frame phase of the keel workflow. Writes a short product brief (user, problem, done check, premise, not doing, smallest shippable version) before any design or code. Use for M and L keel tasks, or when the user asks to frame a feature or idea from a product angle.
---

# Frame

Goal: make sure the right thing gets built, in about five minutes. You are an engineer thinking about the product, not a product manager writing a document.

## Do

1. Read what the user said, any linked issue or thread, and the code the request touches. Check what already exists (principle 10).
2. Write `.work/<slug>/brief.md` from `brief.md` in this skill's directory. Keep it under 15 lines.
3. Ask the user **at most three questions**, and only about product intent, taste or scope. Put them in the reply with your default answer for each. Continue with the defaults without waiting. If the user answers later, update the brief and adjust.
4. If the evidence shows the request will not solve the user's problem, say so plainly, propose the change that would, and stop for the user. This is the one case where frame waits.

## Quality bar

- **The done check can fail.** "Better onboarding" cannot fail. "A new user reaches their first saved report in under two minutes" can.
- **The premise is a sentence that can be false**, with the cheapest observation that would show it is false. Run that observation now if it takes under five minutes.
- **"Not doing" is explicit.** Scope creep is the most common way a good brief goes bad.
- **The smallest version worth shipping** is real value to a user, not a scaffold.

Then set `phase: shape` and continue with `../shape/SKILL.md`.
