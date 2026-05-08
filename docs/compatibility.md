# Upkeeper Compatibility Contract

Upkeeper is central operational infrastructure. Changes should keep existing
operators and symlinked client repositories working unless there is literally no
responsible way to do so.

Backward compatibility is the default. A breaking change is allowed only when at
least one of these is true:

- Keeping compatibility would preserve a real security or safety risk.
- An external dependency, platform, or Codex behavior change makes compatibility
  impossible.
- The old behavior is provably broken and preserving it would cause materially
  worse failures than rejecting it.

Examples include refusing a risky outdated TLS/SSL behavior, retiring a wrapper
path that can target the wrong repository, or rejecting an input format that can
hide malformed operator data as absence.

## Binding Feature Surface

Future changes should preserve this operator-visible surface as far as possible:

- Root `Upkeeper` remains the executable entrypoint.
- Symlinked clients can continue invoking a local `./Upkeeper.sh` that points to
  the central root `Upkeeper` file.
- The root entrypoint resolves paired modules, prompt files, and documentation
  from the central checkout, not from each client repo.
- Existing documented CLI flags keep working:
  `--help`, `-h`, `--version`, `--prompt-file`, `--prompt`,
  `--model-override=...`, `--target-file=...`, and `--prompt-pass=all`.
- Existing documented environment knobs keep their meaning unless a change note
  states an unavoidable safety reason.
- `CODEX_TERMINAL_VERBOSITY` keeps the documented modes and aliases for
  `basic`, `quiet`, `silent`, `verbose`, `debug1`, and `full`.
- Status-marker contracts remain stable:
  `UPKEEPER_STATUS`, `UPKEEPER_LOG_REVIEW`, `CODEX_POSTMORTEM_STATUS`, and their
  documented status values.
- Published loop exit meanings remain stable, especially successful work,
  intentional no-backend-task stop, fallback/postmortem failures, active locks,
  empty transcripts, local environment failures, and parent-stop guardrails.
- `Upkeeper.log` keeps cycle/run evidence in parseable timestamped lines with
  `cycle=...`, `run_hash=...`, event names, and key-value fields.
- Review summaries continue to log outcome, selected file, findings, changes,
  verification, Codex exit, and final status-marker evidence when available.
- Runtime artifacts stay under documented local paths such as `runtime/`,
  `runtime/upkeeper-transcripts`, and `runtime/journals/upkeeper-postmortems`.
- Validation entrypoints remain available:
  `tools/validate_upkeeper.sh --deps`, `--quick`, and `--full`.
- Default validation and future local stress-corpus checks do not spend backend
  Codex quota unless the operator explicitly opts in.
- Central prompt files remain usable by absolute path from symlinked clients.
- The default review prompt keeps the single-selected-file review contract and
  the P1-P23 pass repertoire, including the P23 data-contract pass.
- Client repos keep `Upkeeper.sh`, `Upkeeper.log`, `runtime/`, and local
  generated operator-guide state out of tracked source unless a client-specific
  issue requires otherwise.

Internal Bash function names, module boundaries, helper implementations, and
prompt wording can change when the operator-visible behavior above remains
compatible.

## Breaking-Change Requirements

If a breaking change is unavoidable:

- Keep a compatibility alias, shim, warning, or migration path when feasible.
- Prefer rejecting unsafe input with a clear diagnostic over silently changing
  behavior.
- Update `UPKEEPER_VERSION`, root `change_notes.md`, README/operator-guide
  docs, and any affected validation coverage in the same committed state.
- State the broken surface, reason compatibility could not be kept, operator
  impact, migration path, and rollback risk.
- Avoid tracked client-repo churn for central wrapper compatibility changes.
