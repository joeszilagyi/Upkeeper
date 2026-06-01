# Architecture Lint

Upkeeper keeps deterministic control-plane work local, cheap, and directly
testable. `tools/check_architecture.py` is the report layer for patterns that
make that harder to preserve as the wrapper grows.

Run:

```sh
tools/validate_upkeeper.sh --architecture-report
```

The report is intentionally mixed-mode:

- `ERROR function-shadow` is fatal unless the duplicate function name appears
  in `config/architecture_lint_allowlist.tsv`.
- `REPORT declare-f-sed-eval` identifies function-text rewriting through
  `declare -f | sed | eval`.
- `REPORT long-inline-python` identifies inline Python heredocs over the
  configured threshold.
- `REPORT shell-loop-process`, `REPORT python-loop-subprocess`, and
  `REPORT python-loop-sql` identify obvious per-row or per-file process and
  database work.
- `REPORT long-bash-function` identifies functions that have outgrown a narrow
  ownership boundary.

## Inline Python Policy

Inline Python is acceptable for short one-off adapters when shell would be
less safe or less readable. It becomes architecture debt when it holds domain
logic, policy decisions, path custody, JSON schemas, or looped hot-path work.

Use this rule for new code:

- Keep inline Python under roughly 40 lines unless there is a specific local
  reason to keep it embedded.
- Move inline Python called from loops or repeated validator phases into an
  importable `tools/upkeeper_lib/*.py` module or a stable CLI wrapper.
- Prefer direct Python unit tests for extracted parsing, selection, custody,
  transcript, manifest, and contract logic.
- Keep shell modules responsible for orchestration and environment binding;
  keep reusable parsing and state-machine logic importable.

Existing long heredocs remain report-only while their owner issues are worked
down. New exceptions should be rare and should name the reason in the code or
the architecture report allowlist.
