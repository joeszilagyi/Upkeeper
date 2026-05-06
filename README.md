# Upkeeper

Upkeeper is a small local toolkit for keeping repositories tidy, reviewable, and easy to resume.

## Purpose

This repository holds reusable maintenance prompts, prompt templates, and the `Upkeeper` operator script.
The goal is to keep project-care workflows explicit, portable, and easy to evolve.

## License

This repository is released under the `0BSD` license.

## Structure

```text
.
|-- Upkeeper
|-- prompts/
|   `-- README.md
|-- templates/
|   |-- README.md
|   `-- prompt-template.md
|-- .editorconfig
|-- .gitignore
`-- README.md
```

## How To Use

1. Start from [`templates/prompt-template.md`](templates/prompt-template.md) for reusable prompts.
2. Put focused prompt files under `prompts/`.
3. Run `./Upkeeper --help` to inspect the local operator options.
4. Update wording based on real usage instead of trying to make prompts perfect on the first pass.

## Suggested Prompt Format

Use a simple structure such as:

- Title
- Goal
- When to use it
- Inputs
- Prompt
- Notes

This is intentionally minimal so the repo can grow without being locked into a rigid schema too early.
