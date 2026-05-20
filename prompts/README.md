# Prompts

Store finished or in-progress prompts in this directory.

Tracked prompts:

- [`default-review.md`](default-review.md) - runtime template loaded by Upkeeper.
- [`caretaking_23_items.md`](caretaking_23_items.md) - full rotating review repertoire reference.
- [`git_hard_clean.md`](git_hard_clean.md) - focused branch and backup cleanup prompt.
- [`p23-data-contract-negative-fixture-audit.md`](p23-data-contract-negative-fixture-audit.md) - standalone P23 add-on prompt.
- [`p24-de-llm-ing-viability-review.md`](p24-de-llm-ing-viability-review.md) - P24 opt-in review module for de-LLM-ing viability.
- [`p25-contract-intent-compliance-review.md`](p25-contract-intent-compliance-review.md) - P25 opt-in review module for contract and intent compliance.
- [`p26-public-documentation-review.md`](p26-public-documentation-review.md) - P26 opt-in review module for public documentation and comment clarity.
- [`p27-educational-debrief-review.md`](p27-educational-debrief-review.md) - P27 opt-in review module for a concise saved learning debrief.
- [`p28-unit-test-harvesting-review.md`](p28-unit-test-harvesting-review.md) - P28 opt-in review module for turning useful discoveries into local tests or fixtures.
- [`p29-reuse-harvesting-review.md`](p29-reuse-harvesting-review.md) - P29 opt-in review module for extracting bounded reusable helpers, fixtures, prompt language, docs, and validation patterns.
- [`p30-stark-protocol-review.md`](p30-stark-protocol-review.md) - P30 opt-in review module for permanent hardening and non-regression barriers.
- [`p31-fault-injection-review.md`](p31-fault-injection-review.md) - reserved future P31 contract for deterministic fault-injection scenarios with explicit oracles and recovery proof; not wired as a `--review-module` flag yet.

Reusable review-module contract:

All files matching `prompts/pNN-*.md` intended as reusable review modules should keep a shared structure so future modules can be validated consistently:

- A clear title/header (typically `# PNN ...`)
- A bounded scope section (applicability and non-goals/boundaries)
- A trigger/assumption section
- Verification guidance (what to run locally before/after applying)
- An output contract + final status/marker discipline
- A discoverability section covering prompt index/help/compatibility visibility

When adding or modifying a prompt module:

1. Keep this index current with the module file.
2. Keep operator-facing help/docs/compatibility docs updated when visibility changes.
3. Add a structural-check in `tools/validate_upkeeper.sh` (or an equivalent validator) so drift fails fast instead of being rediscovered later.
4. Add/update a focused prompt or fixture to enforce the new contract.

Numbering compatibility:

- P29 remains the public reuse-harvesting review module and its aliases keep
  that meaning.
- P30 remains the Stark Protocol permanent-hardening module.
- Fault-injection review is reserved for future P31 work, or for a later named
  module with an explicit non-breaking alias plan. The tracked P31 prompt
  defines the contract before wiring.

Guidelines:

- Keep one prompt per file.
- Use clear filenames such as `meeting-summary.md` or `code-review-checklist.md`.
- Prefer practical prompts that solve a specific task.
- Revise prompts based on real outputs and failure cases.

If you are starting a new prompt, copy the template from `../templates/prompt-template.md`.
