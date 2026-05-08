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
  `--help`, `-h`, `--version`, `--config-file=...`, `--no-config`,
  `--prompt-file`, `--prompt`,
  `--review-module=...`, `--review-modules=...`, `--p24`, `--p25`, `--p26`,
  `--p27`, `--p28`, `--model-override=...`, `--target-file=...`, and
  `--target-root=...`, `--target-depth=...`,
  `--selection-source=manifest|enumerate`,
  `--selection-order=oldest|newest|random`, `--refresh-manifest`,
  `--manifest-file=...`, `--include-glob=...`, `--include-globs=...`,
  `--exclude-glob=...`, `--exclude-globs=...`,
  `--selection-review-modules=...`, `--ignore-failure-queue`, and
  `--prompt-pass=all`.
- The central default config remains `Upkeeper.conf`, and named config profiles
  can be selected per invocation with `--config-file=PATH`.
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
  `runtime/upkeeper-transcripts`, `runtime/journals/upkeeper-postmortems`,
  `runtime/upkeeper-file-manifest.json`, and
  `runtime/unaddressed-tool-failures`.
- Validation entrypoints remain available:
  `tools/validate_upkeeper.sh --deps`, `--quick`, and `--full`.
- Default validation and future local stress-corpus checks do not spend backend
  Codex quota unless the operator explicitly opts in.
- Central prompt files remain usable by absolute path from symlinked clients.
- Central review modules remain usable by flag from symlinked clients.
- Local unaddressed tool-failure markers can prioritize the next eligible target
  without changing tracked source; operator `--target-file` and
  `--ignore-failure-queue` still override that local queue for one cycle.
- Config files can provide scheduled-run defaults, but CLI flags remain the
  final one-cycle override surface.
- The default target rotation is manifest-backed when a current local manifest
  exists or can be built. Direct enumeration remains available through
  `--selection-source=enumerate`, and operator-pinned `--target-file` keeps
  priority over manifest, queue, and filter behavior.
- Explicit `--target-file` pins may select any source-safe readable text file
  inside the repo, including docs, prompts, config, tests, and scripts, while
  automatic rotation remains limited to script/tool candidates.
- Selection filters such as target root, depth, include/exclude globs, random
  order, and review-module approximations narrow which file Upkeeper chooses.
  They do not silently enable extra review modules or change the single-selected-
  file prompt contract.
- Public documentation, help text, prompt docs, code comments, and release
  notes remain understandable enough for public review without private context.
- The default review prompt keeps the single-selected-file review contract and
  the P1-P23 pass repertoire, including the P23 data-contract pass.
- Client repos keep `Upkeeper.sh`, `Upkeeper.log`, `runtime/`, and local
  generated operator-guide state out of tracked source unless a client-specific
  issue requires otherwise.

Internal Bash function names, module boundaries, helper implementations, and
prompt wording can change when the operator-visible behavior above remains
compatible.

## Maintainability And Simplicity Requirements

Future compatibility work should make Upkeeper easier to maintain, not only
larger.

- Prefer small reusable local functions for behavior that is repeated, parsed,
  logged, validated, or relied on by more than one module.
- Keep the root `Upkeeper` entrypoint focused on orchestration; put reusable
  behavior in `lib/upkeeper` modules with clear ownership.
- Start with the smallest sufficient mechanism: a Bash helper, existing command,
  focused Python parser, fixture, or validation check is preferred over a new
  framework, service, daemon, database, or background runtime.
- Add new dependencies only when the existing local toolchain would make the
  solution materially less safe, less clear, or less testable.
- Do not over-fragment one-off code. Split or extract only when it reduces real
  coupling, removes meaningful duplication, clarifies a contract, or makes a
  behavior easier to verify.
- Prefer deterministic local code for stable parsing, classification,
  formatting, routing, preflight, and guardrail enforcement. Keep LLM-backed
  paths for open-ended review, ambiguous judgement, and remediation planning.
- When a helper becomes part of a contract, add focused validation coverage for
  both normal and malformed paths.
- Avoid introducing a larger runtime system for a problem solved by a small
  local helper. The simplest tool that satisfies the documented contract is the
  preferred tool.

## Breaking-Change Requirements

If a breaking change is unavoidable:

- Keep a compatibility alias, shim, warning, or migration path when feasible.
- Prefer rejecting unsafe input with a clear diagnostic over silently changing
  behavior.
- Update `UPKEEPER_VERSION`, the current year's root `change_notes_YYYY.md`,
  README/operator-guide docs, and any affected validation coverage in the same
  committed state.
- State the broken surface, reason compatibility could not be kept, operator
  impact, migration path, and rollback risk.
- Avoid tracked client-repo churn for central wrapper compatibility changes.
