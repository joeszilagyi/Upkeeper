# Upkeeper

Upkeeper is a small local toolkit for keeping repositories tidy, reviewable,
and easy to resume.

## Purpose

This repository holds:

- the `Upkeeper` operator script for running one guarded Codex maintenance
  cycle at a time
- reusable maintenance prompts and prompt templates
- operator documentation for running, debugging, and evolving the wrapper

The goal is to keep project-care workflows explicit, portable, and easy to
audit after the fact.

## Operator Script

`./Upkeeper` is the active wrapper in this repo. It reads Codex quota snapshots,
logs each cycle, runs one backend task, and can hand off to a bounded fallback
cycle when guardrails or failures make that safer.

Useful commands:

```sh
./Upkeeper --help
./Upkeeper --version
UPKEEPER_DRY_RUN=1 ./Upkeeper
```

Typical loop:

```sh
while ./Upkeeper; do
  sleep 60
done
```

The detailed operator guide is [docs/scripts/upkeeper.md](docs/scripts/upkeeper.md).

Local run evidence is intentionally not tracked in git:

- `Upkeeper.log`
- `runtime/`

## License

This repository is released under the `0BSD` license.

## Structure

```text
.
|-- docs/
|   `-- scripts/
|       `-- upkeeper.md
|-- prompts/
|   `-- README.md
|-- templates/
|   |-- README.md
|   `-- prompt-template.md
|-- Upkeeper
|-- caretaking_22_items.md
|-- git_hard_clean.md
|-- LICENSE
|-- .editorconfig
|-- .gitignore
`-- README.md
```

## How To Use

1. Start from [`templates/prompt-template.md`](templates/prompt-template.md) for reusable prompts.
2. Put focused prompt files under `prompts/`.
3. Use [`caretaking_22_items.md`](caretaking_22_items.md) for the rotating
   single-file maintenance review prompt.
4. Use [`git_hard_clean.md`](git_hard_clean.md) for explicit branch and backup
   cleanup workflows.
5. Run `./Upkeeper --help` to inspect the local operator options.
6. Update wording based on real usage instead of trying to make prompts perfect
   on the first pass.

## Suggested Prompt Format

Use a simple structure such as:

- Title
- Goal
- When to use it
- Inputs
- Prompt
- Notes

This is intentionally minimal so the repo can grow without being locked into a rigid schema too early.
