# Prompt Module Template

Use this template for `prompts/pNN-*.md` files that are meant to be reusable and
invoked repeatedly by review-module flags.

## 1) Purpose and Scope

- What is this module for?
- When should an operator request it?
- What is explicitly out of scope?
- Which file types, surfaces, or boundaries does it target or avoid?

## 2) Trigger / Applicability

- Include an explicit applicability statement (for example:
  `PNN: not applicable` when not in scope).
- If applicable, include clear trigger conditions and the boundary that makes the
  module necessary.

## 3) Verification Guidance

- Document what should be run to validate this module locally.
- Include the expected minimum evidence shape for module fixes or findings.

## 4) Output Contract

- Specify the expected final response shape for this module.
- Include the keys/sections required in final output.

## 5) Final Marker Discipline

- Restate the required final response marker contract and any blocked/fallback
  behavior.
- Keep output markers consistent with the enclosing run contract.

## 6) Discoverability and Compatibility

- Note where this module is exposed (docs/help/compatibility).
- Include any visibility or aliasing constraints (for example `--review-module=`
  wiring and numeric compatibility notes).
