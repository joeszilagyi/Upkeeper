# P27 After-Action Review

Use this as an Upkeeper review module when you want the run to leave behind a
concise after-action review, not only a fix.

P27 is for operators who want Upkeeper to improve the repository and improve the
human feedback loop at the same time. Professionals can adapt the lesson into
team practice. Hobbyists can use it to spend spare cycles on backlog and learn
what went right, what went wrong, what was wasteful, and how to avoid the same
shape later.

Self-optimization is part of this module. A meaningful operation should be able
to yield a compact lesson about reducing repeated LLM work, tightening local
airlocks, improving operator clarity, or making clean no-op paths faster and
more trustworthy.

This module does not replace normal selected-file review. Follow the normal
selected-file rule and all normal applicable P1-P26 instructions. In addition,
run P27 when the selected-file review finds a real bug, clarity gap, contract
drift, missing validation, brittle assumption, avoidable complexity, or useful
positive practice worth calling out.

If there is no meaningful lesson from the selected-file review, state
`P27: not applicable` and proceed with the normal applicable review only.

## Scope and Boundaries

Use P27 only when a single run produces a durable lesson beyond normal findings and
the lesson can be stated as reusable operator guidance in transcript output.
Do not use P27 for routine dry edits with no recurring operator value.
Do not apply P27 to runs where another module already owns the behavior change and
no additional debrief is useful.

`P27: not applicable` is the boundary when no lesson applies.

## Verification Guidance

If P27 applies, verify that the selected-file response includes:

- the required final-response block
- a clear explanation of what happened and why it matters
- at least one actionable "how to avoid it" point
- whether any follow-up verification was run in this run

No extra tooling is required beyond the normal selected-file work.

## P27 - After-Action Review

Goal:

After fixing or reviewing the selected file, write a lean after-action review
that explains the lesson in plain engineering language.

The review should help a future reader understand:

- outcome summary
- what went right
- what went wrong
- why it probably happened
- why it mattered
- what was wasteful
- how to avoid the same pattern
- how the fix addressed it
- whether the system learned anything reusable
- what could still be improved later

Do not turn this into a tutorial on basic syntax. Do not shame the original
author. Most mistakes come from local context, hidden contracts, evolving
requirements, unclear feedback loops, or missing fixtures. Explain those causes
practically.

### Saved Structure

The normal Upkeeper transcript and parsed finale already preserve the final
response. Keep the educational note in that saved response unless the lesson
belongs in a durable tracked doc.

Use this compact structure:

```text
P27 After-Action Review:
- Outcome:
- What went right:
- What went wrong:
- Why it probably happened:
- Why it mattered:
- What was wasteful:
- How to avoid it:
- How it was fixed:
- Reusable learning:
- What can improve next time:
```

Each bullet should usually be one or two sentences. If there was no bug but
there was a useful clean review, keep the review shorter and focus on the
outcome, what went right, waste avoided, and what to watch later.

### When To Add A Tracked Doc

Do not create a new doc file for every lesson.

Add or update tracked docs only when:

- the lesson is a recurring operator rule
- the lesson changes public behavior
- the lesson belongs in `README.md`, `docs/scripts/upkeeper.md`,
  `docs/compatibility.md`, `docs/public-documentation-policy.md`, or a module
  README
- the lesson should guide future agents beyond this single transcript

Otherwise, the saved transcript/finale is enough.

### Good Debrief Style

Prefer:

- balanced signal from success, failure, and cost
- concrete behavior over abstract blame
- one root cause, or two at most
- direct names for files, flags, env vars, logs, markers, or functions
- practical avoidance advice
- credit for the part that already worked

Avoid:

- moralizing
- vague "be careful" advice
- fake certainty about the original author's intent
- long essays
- repeating the normal change summary without explaining the lesson

### Output Contract

When P27 applies, include exactly one `P27 After-Action Review:` block in the
final response using the saved structure above.

If P27 does not apply, include:

`P27: not applicable`

### Final Marker Discipline

The final response must still include exactly one normal Upkeeper final marker:

- `UPKEEPER_STATUS: WORK_DONE`
- `UPKEEPER_STATUS: BLOCKED`

Do not invent a P27-specific final status marker.
