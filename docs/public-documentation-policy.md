# Public Documentation Policy

Upkeeper treats every committed release, patch, prompt, help update, code
comment, and operator-facing message as public project material.

The current checked-in state is always the thing being delivered. Do not write
as if the real product arrives later. A patch may be small, but it should still
leave the repository confident, current, and understandable.

The practical rule is simple: a reader should be able to open the repository,
pick a tracked file or line, and understand the important intent without private
chat history. The reader may be a developer, security reviewer, operator,
hobbyist, future maintainer, or digital agent.

This policy does not require explaining basic programming syntax. It does
require explaining Upkeeper-specific intent, contracts, safety boundaries, and
operator-visible behavior when names and structure are not enough.

## Writing Standard

Use public, practical engineering language.

Prefer:

- direct sentences
- concrete names for files, flags, env vars, logs, markers, and modules
- short examples that match real commands
- comments that explain intent or safety boundaries
- release notes that describe operator impact
- docs that tell the reader where to go next

Avoid:

- placeholder prose
- private shorthand from chat sessions
- formal wording that sounds precise but hides the behavior
- arbitrary subsection labels or fake legal structure
- repeating obvious syntax in comments
- stale TODO-style promises without a tracked reason

The goal is not more words. The goal is useful words with a little operational
confidence. Upkeeper is allowed to sound like a tool that works.

## Code Comments

Code comments should earn their place.

Add or keep comments when they explain:

- what a function owns
- why a guardrail exists
- what external contract a parser, log field, status marker, or exit code must
  preserve
- why a surprising branch is safe
- what a helper intentionally refuses to do

Remove or rewrite comments when they only repeat the code, describe old
behavior, or use formal prose without clarifying the intent.

## Documentation Flow

Tracked docs should form a readable path:

- `README.md` explains the project purpose, normal use, and repository layout.
- `docs/scripts/upkeeper.md` explains operator behavior, flags, environment
  knobs, logs, exits, and examples.
- `docs/compatibility.md` defines stable public contracts.
- `docs/dependencies.md` defines runtime and validation dependencies.
- `docs/stress-corpus.md` defines sample-repo stress testing intent.
- `lib/upkeeper/README.md` explains module ownership and load-order discipline.
- `prompts/README.md` indexes prompt and review-module contracts.
- Root annual `change_notes_YYYY.md` files record public release impact.

When behavior changes, update the smallest set of paired docs needed to keep
that path true.

## Release And Patch Rule

Every release or patch should be understandable as public history.

For notable changes:

- bump the wrapper version when committed wrapper behavior changes
- add a dated entry to the current year's root `change_notes_YYYY.md`
- describe what an operator can observe
- update `--help` and `docs/scripts/upkeeper.md` together when CLI behavior
  changes
- update README or policy docs when project direction changes
- add validation when the rule is deterministic enough to check locally

Do not rely on an issue, PR comment, chat transcript, or terminal scrollback as
the only explanation of a committed behavior.

## Enforcement

P26 is the judgment pass for this policy:

```sh
./Upkeeper --review-module=p26
```

The local checker catches deterministic public-doc drift:

```sh
tools/check_public_docs.sh
```

`tools/validate_upkeeper.sh --quick` runs the checker as part of the normal
Upkeeper validation harness.

P27 is the saved learning pass for useful fixes:

```sh
./Upkeeper --review-module=p27
```

Use it when a run should explain what went wrong, why it probably happened, why
it mattered, how the fix addresses it, what was already good, and what still
can improve. Keep that note concise unless the lesson belongs in tracked docs.

P28 is the unit-test harvesting pass:

```sh
./Upkeeper --review-module=p28
```

Use it when a bug, reusable exploratory command, parser edge case, validation
path, or deterministic model-discovered fact can become a cheap local test or
fixture that runs without backend model quota.
