# P23 Data Contract And Negative Fixture Audit

Use this as an Upkeeper `--prompt-file` add-on when you want an explicit P23
focus on top of the built-in maintenance prompt.

This add-on does not replace the existing Upkeeper review repertoire. Follow the
normal selected-file rule and all normal applicable P1-P22 instructions. In
addition, run this P23 pass if the selected file is any of the following:

- validator
- parser
- importer
- exporter
- registry loader
- schema/profile helper
- config/manifest reader
- JSON/JSONL/YAML/CSV/SQLite reader
- shell helper that resolves paths, consumes env/argv, publishes files, or
  invokes subprocess output
- CLI tool that reads user/operator-supplied files or emits machine-readable
  output

If the selected file does not touch a data/input boundary, state
`P23: not applicable` and proceed with the normal applicable P1-P22 review only.

## P23 - Data Contract And Negative Fixture Audit

Goal:

Find places where malformed, ambiguous, unsafe, or non-contract data is accepted,
coerced, silently ignored, partially applied, or reported without actionable
diagnostics.

Core principle:

A tool is not contract-safe merely because valid fixtures pass. It must reject
malformed inputs early, explicitly, and with diagnostics that make the bad
field, row, path, or logical target clear without leaking secrets.

### 1. Boundary Inventory

Identify every external or semi-external input boundary in the selected file.

Check for:

- argv / CLI flags
- environment variables
- stdin
- filesystem paths
- JSON files
- JSONL rows
- YAML or JSON-compatible YAML registries
- CSV or delimiter-based records
- SQLite rows
- schema/profile/manifest documents
- URL fields
- subprocess stdout/stderr
- generated artifacts from earlier pipeline stages
- caller-provided Python dictionaries/lists
- shell function parameters

For each meaningful boundary, ask: where is the first trusted point, and is
validation performed before the data influences behavior?

### 2. Contract Strictness

For every boundary, check whether malformed or non-contract data is rejected
rather than accepted, coerced, skipped, or silently defaulted.

Look specifically for failure to reject:

- unexpected fields where the contract is meant to be closed
- missing required fields
- wrong top-level container types
- wrong nested container types
- non-object rows inside object arrays
- duplicate normalized IDs, keys, predicates, claim types, aliases, schemes, or
  policy IDs
- blank strings where nonblank strings are required
- strings accepted where booleans are required
- strings accepted where numbers are required
- booleans accepted where integers or numbers are required
- `NaN`, `Infinity`, `-Infinity`, or any non-standard JSON numeric constants
- non-finite floats
- out-of-range scores, thresholds, counts, limits, or confidence values
- negative counts where only nonnegative counts are meaningful
- invalid timestamp format or timestamps without explicit timezone when timezone
  matters
- invalid URL schemes
- credential-bearing URLs such as `https://user:pass@example.org`
- local paths that are actually URLs
- path traversal or resolved paths escaping the allowed root
- paths accepted because they merely contain a directory name rather than
  matching the exact required layout
- conflicting duplicate fields between top-level and nested representations
- ambiguous records that should be rejected or require human review
- unknown enum values
- deprecated enum aliases that should warn or normalize explicitly
- unsupported schema/profile versions

### 3. No Silent Coercion

Search for coercion or fallback patterns that can convert bad input into
plausible output.

Flag uses of:

- `str(value)` on contract fields where non-string types should be rejected
- `bool(value)` on JSON/config values, especially where `"false"` would become
  truthy
- `int(value)` or `float(value)` without finite/range checks
- default `{}` or `[]` that hides malformed caller data
- `row.get(...)` followed by quiet skip when the field is required
- list comprehensions that silently drop non-object rows
- broad `except Exception` that treats malformed input as absence
- `json.loads(...)` without rejecting non-standard constants when strict JSON is
  expected
- duplicate-key or duplicate-normalized-value overwrites
- "first match wins" behavior where duplicates should be errors
- fallback-to-empty behavior that causes validators/exporters to pass with
  partial data

Do not mechanically remove every coercion. Only flag it when it can hide a real
contract violation or produce misleading output.

### 4. Diagnostics And Failure Contract

For each validation failure path, check whether the error is useful and safe.

Good diagnostics should include, where practical:

- field name
- nested path
- row index
- JSONL line number
- registry row index
- offending enum/key name
- expected type/range/pattern
- target path or logical target ID
- clear exit code behavior for CLI tools

Diagnostics should not leak:

- embedded credentials
- tokens
- full sensitive URLs if credentials are present
- large raw payloads
- private/local-only content beyond what is needed to debug safely

Flag failures that only say `invalid input`, `KeyError`, `AttributeError`,
`ValueError`, `failed`, or emit a Python traceback for normal malformed operator
input.

### 5. Negative Fixture Requirement

If you implement a P23 boundary fix, add or update a focused negative test or
fixture unless there is a clear reason not to.

A valid negative test should prove the previous permissive behavior is now
rejected. Prefer small tests that exercise one defect at a time.

Strong negative fixture examples:

- JSONL line with `NaN`
- JSON boolean in an integer field
- duplicate normalized registry keys
- non-object row inside an array
- unexpected key in closed contract
- credential-bearing remote URL
- path with correct-looking words but wrong root layout
- top-level and nested retention/status fields disagree
- unknown enum value
- invalid timestamp without timezone
- missing required field inside one array row
- malformed profile condition
- missing `--work-id` target that previously returned success

Normal-path tests alone are not enough for P23 fixes.

### 6. Schema-Code-Doc Alignment

When the selected file has paired schemas, docs, fixtures, or callers, inspect
only enough adjacent context to verify alignment.

Compare:

- schema vs validator
- validator vs parser/importer
- parser/importer vs exporter
- registry file vs registry loader
- CLI help vs behavior
- docs vs code
- existing tests/fixtures vs expected contract
- output report shape vs documented output contract

Flag drift in any direction. A schema that is stricter than the validator is a
bug. A validator that is stricter than the docs may be a docs bug or a behavior
bug; decide based on surrounding contract evidence.

### 7. Output/Export Integrity

For exporters and report writers, check that malformed or ambiguous internal
records do not create plausible but wrong downstream output.

Look for:

- inverse relationships projected as forward relationships
- lossy fields emitted without warning when the format cannot represent them
- identifiers dropped when multiple standard values exist
- unsafe escaping in text formats
- invalid XML/JSON/CSV/BibTeX/RIS escaping
- whitespace/newline behavior that changes record meaning
- local/private data leaking into public formats
- missing loss report entries for known omissions
- output written non-atomically when partial output would be misleading

### 8. Read-Only, Dry-Run, And Mutation Claims

If the tool claims to be read-only, dry-run, validation-only, metadata-only, or
temp-copy-only, verify that claim against the actual code.

Flag:

- read-only tools opening SQLite through normal write-capable connections
- dry-run modes that still mutate durable state
- validation-only modes that write artifacts outside explicit report paths
- temp-copy import flows that can write the source DB
- report writers that can leave partial files on interruption
- copy flows that race on predictable filenames
- cleanup paths that leave stale temp files after failure

## Process

1. Run normal P1-P22 as instructed by the base Upkeeper prompt.
2. If P23 applies, inspect the selected file plus only directly paired
   schemas/docs/tests/callers needed to judge contracts.
3. Propose P23 findings before applying changes.
4. Apply only high-confidence, localized fixes.
5. For every applied P23 fix, add or update a focused negative test unless not
   practical; if not practical, explain why.
6. Run at least these verification paths when changes are made:
   - syntax/compile check for edited source
   - normal valid path
   - malformed/negative path
   - relevant focused test file or fixture suite
   - `git diff --check`
7. Verify persisted file contents and mtime as required by the base prompt.
8. Keep the final response concise but explicit about which P23 categories found
   issues.

## Output Requirements

Include a `P23` section in the final report with:

- `P23 applicability`: applicable or not applicable, with reason
- `Input boundaries inspected`: concise list
- `Contract defects found`: concise findings, or `none`
- `Fixes applied`: concise list, or `none`
- `Negative tests added/updated`: list, or reason omitted
- `Schema/code/doc alignment`: aligned, updated, or deferred
- `Residual risks`: concise, especially if adjacent context was too broad to
  inspect

## Rules

- No busy work.
- No cosmetic-only changes.
- Do not broaden the task beyond the selected file and directly paired contract
  context.
- Do not turn P23 into a general refactor.
- Do not silently tighten public behavior without tests and a clear rationale.
- Do not add fake dry-run/check behavior that still mutates state.
- Do not add negative tests that only assert implementation details.
- If the contract is ambiguous, document the ambiguity and stop short of
  guessing unless surrounding evidence is strong.
- If malformed input can create plausible but wrong output, treat that as high
  value.
- If a valid input path is already well covered but malformed inputs are not,
  that is a real P23 test gap.

## Short Inline Version

Also run experimental P23 when applicable: Data Contract and Negative Fixture
Audit. Apply it only if the selected file is a validator, parser, importer,
exporter, registry loader, schema/profile helper, config/manifest reader,
JSON/JSONL/YAML/CSV/SQLite reader, path-resolving shell helper, or CLI that
consumes external/operator input. Inventory boundaries; check strict rejection
of malformed/non-contract data including unexpected keys, wrong containers,
non-object rows, duplicate normalized IDs, blank required strings,
booleans-as-ints, NaN/Infinity, non-finite/out-of-range numbers, invalid
timestamps, credential-bearing URLs, path traversal/wrong roots,
top-level/nested disagreement, unknown enums, and unsupported versions. Flag
silent coercion via str(), bool(), default {} or [], broad catches, skipped
malformed rows, duplicate overwrites, and fallback-to-empty behavior. Ensure
diagnostics identify field/path/row/line without leaking secrets. For every
boundary fix, add or update a focused negative test/fixture unless impractical.
Compare schema, code, docs, fixtures, and callers for drift. For exporters and
report writers, check escaping, inverse relationship projection, dropped
identifiers, private-data leakage, loss reporting, and atomic output. For
read-only/dry-run claims, verify no durable mutation occurs. Keep fixes local,
high-confidence, tested, and non-cosmetic. In final output include P23
applicability, boundaries inspected, defects found, fixes applied, negative
tests, schema/code/doc alignment, and residual risks.
