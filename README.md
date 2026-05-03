# Useful LLM Prompts

A lightweight home for reusable prompts, prompt patterns, and prompt templates.

## Purpose

This repository is set up as a simple prompt library rather than an application.
The goal is to keep good prompts easy to find, easy to reuse, and easy to evolve.

## License

This repository is released under the `0BSD` license.

## Structure

```text
.
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

1. Start from [`templates/prompt-template.md`](templates/prompt-template.md).
2. Create a new prompt file under `prompts/`.
3. Keep each prompt focused on one job or workflow.
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
