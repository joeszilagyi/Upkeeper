# Upkeeper Lattice

Upkeeper Lattice is a local SQLite evidence ledger and selection-intelligence
layer for file-affecting Upkeeper activity. It is on by default and writes to:

```text
runtime/upkeeper-lattice/lattice.sqlite3
```

That path is ignored runtime state. The live database, rollback journal,
optional WAL side files, backups, exports, recovery records, transcripts, and
raw local logs must not be committed.

## What Lattice Is

Lattice records local evidence that helps Upkeeper explain and recover file
work over time:

- candidate generation and exclusion
- target selection and selection basis
- selected-file snapshots
- worktree snapshots before and after cycles
- pass planning and pass results
- clean touches, changed files, and dirty baselines
- tool-failure markers and resolutions
- regression evidence and corrections
- local Git imports
- changelog imports
- `Upkeeper.log` imports
- JSONL export/import/recovery activity
- artifact references
- operator annotations
- namespaced extension facts

When Lattice rows or exports need to connect cycles, runs, targets, prompts,
backups, artifacts, validation, or config evidence across records, they should
use the stable `upk:` identifier namespace defined in
`docs/run-bom-identifiers.md`. Those ids are evidence links, not a promotion of
Lattice to sole custody authority.

The database is append-friendly and normalized. Future P* passes are represented
as rows in `review_passes` and `file_pass_runs`, not as schema columns. Pass
attributes are rows in `pass_run_attributes` or namespaced extension facts.
Arbitrary user facts belong in `extension_namespaces`, `extension_fact_types`,
and `extension_facts`; they are not arbitrary columns on core tables.

## What Lattice Is Not

Lattice is not an external daemon, ORM, hosted database, CI replacement, GitHub
sync engine, or shared enterprise multi-writer SQLite server. It can run as a
short-lived per-cycle local service process when
`UPKEEPER_LATTICE_SERVICE_ENABLED=1`, but that service is owned by the current
wrapper process, uses stdin/stdout IPC, exits during cycle cleanup, and does not
make network calls or store GitHub tokens.

Lattice does not replace Git or tracked source. Git and the working tree remain
canonical for code. Lattice records evidence about what Upkeeper observed and
did. In short, source-safe live eligibility remains authoritative: current
selection still starts from live local files, ignores `.git/`, `runtime/`,
`Upkeeper.log`, Git-ignored files, `.upkeeperignore` paths, generated outputs,
caches, and vendor content, and then applies explicit target, startup-anomaly,
and failure-queue priority rules before normal oldest-mtime rotation.

Lattice is supporting evidence, not sole custody authority, for audit,
breadcrumb, anomaly, or automation-obligation decisions while the known Lattice
integrity blockers tracked in issues #112, #113, #115, #116, #117, and #118
remain open. Custody decisions must continue to have fallback
log/transcript/runtime evidence available, such as local log lines, transcript
files, runtime breadcrumb JSON, automation obligations, or tool-failure queue
records. A future Lattice-derived custody decision must either confirm against
that fallback evidence or fail closed with a local explanation when the fallback
evidence is unavailable.

The current breadcrumb audit and startup gate do not require Lattice. They read
logs, transcript directories, automation-obligation records, tool-failure queue
records, and `runtime/upkeeper-breadcrumbs` JSON directly so custody can still
work when Lattice is unavailable or when its integrity policy is deliberately
weaker than the live local evidence.

## Defaults

The tracked configs define:

```sh
UPKEEPER_LATTICE_ENABLED=1
UPKEEPER_LATTICE_REQUIRED=0
UPKEEPER_LATTICE_DB="$ROOT_DIR/runtime/upkeeper-lattice/lattice.sqlite3"
UPKEEPER_LATTICE_SELECTION_MODE=oldest-mtime
UPKEEPER_LATTICE_RAW_STORAGE=limited
UPKEEPER_LATTICE_SQLITE_JOURNAL_MODE=delete
UPKEEPER_LATTICE_SERVICE_ENABLED=1
```

`UPKEEPER_LATTICE_ENABLED=1` means every wrapper cycle attempts to initialize,
doctor, and record evidence. `UPKEEPER_LATTICE_REQUIRED=0` means a local DB
problem logs one warning, writes a small recovery JSONL record when possible,
and continues existing Upkeeper behavior. Optional degraded-mode warnings are
not anonymous: the `lattice.unavailable` log line includes a reason class,
`owner_issue=430`, `owner_contract=advisory_lattice_degraded`, and
`replacement_evidence=local_logs_runtime_obligations`. Recovery JSONL rows carry
the same ownership fields plus the bounded `detail_summary`; raw failure detail
stays in private local recovery evidence. Set `UPKEEPER_LATTICE_REQUIRED=1`
when a run must fail before Codex launch if Lattice is unavailable.
`UPKEEPER_LATTICE_SERVICE_ENABLED=1` means those cycle hooks share a warm local
Python process instead of launching a cold `tools/upkeeper_lattice.py` process
for every Lattice event. Set it to `0` to force the legacy one-command-per-spawn
CLI path for diagnosis.

The default SQLite journal mode is rollback journal (`delete`). WAL is opt-in
with `UPKEEPER_LATTICE_SQLITE_JOURNAL_MODE=wal`; when WAL is enabled,
`lattice.sqlite3-wal` and `lattice.sqlite3-shm` are treated as ignored runtime
side files.

When possible, Upkeeper creates:

- `runtime/upkeeper-lattice/` with mode `700`
- `lattice.sqlite3` with mode `600`
- backup files with mode `600`
- export files with mode `600`
- recovery records with mode `600`

`docs/preservation-policy.md` classifies live Lattice databases and recovery
records as warm `private-operator` evidence by default, and Lattice JSONL
exports as cold `private-operator` evidence unless separately sanitized for
public use. Export redaction defaults are part of that preservation contract.

## Tool

The standalone CLI is:

```sh
tools/upkeeper_lattice.py --root "$PWD" --db runtime/upkeeper-lattice/lattice.sqlite3 init
tools/upkeeper_lattice.py doctor
tools/upkeeper_lattice.py backup
tools/upkeeper_lattice.py export-jsonl
tools/upkeeper_lattice.py query least-reviewed
```

Every SQLite connection enables:

- `PRAGMA foreign_keys=ON`
- `PRAGMA busy_timeout=5000`

`doctor` checks DB readability and writability, parent directory state and
permissions, ignored-path safety, schema version, `PRAGMA user_version`,
foreign-key enablement, `PRAGMA foreign_key_check`, `PRAGMA quick_check`,
required tables, required indexes, rollback-able writes, side-file safety, and
optional backup creation.

Stable exit codes are:

```text
0 success
1 no query rows when --fail-on-no-match is used
2 usage error
3 DB unavailable
4 unsafe DB path
5 schema mismatch
6 foreign key or integrity failure
7 git unavailable for a git-required command
8 import conflict above allowed threshold
9 recovery incomplete
```

## Schema

Schema version 1 creates the required core tables:

```text
schema_meta
schema_migrations
repositories
repo_aliases
source_records
files
file_paths
file_snapshots
worktree_snapshots
worktree_snapshot_paths
cycles
cycle_links
selection_runs
selection_candidates
review_passes
file_pass_runs
pass_run_attributes
run_values
file_events
artifact_refs
contributors
git_commits
git_file_changes
tool_failures
tool_failure_samples
regression_events
regression_causes
regression_corrections
change_log_entries
change_log_file_refs
lattice_imports
lattice_import_conflicts
lattice_exports
import_cursors
extension_namespaces
extension_fact_types
extension_facts
operator_annotations
```

Rollup tables are also present for pass, fragility, Git churn, selection, and
failure summaries. They are derived summaries; core repo/file/cycle/pass/git
facts are not deleted by default pruning.

Worktree snapshots store dirty-path counts by default. Path-level snapshot
inventory is opt-in and stores path HMACs plus coarse path classes instead of
raw dirty or untracked filenames; those opt-in rows are not linked into the raw
`files` or `file_paths` inventory.

## Pass Counts

“Net times through P*” means `completed_count`.

`completed_count` includes:

- `clean`
- `fixed`
- `regression_found`

`completed_count` excludes:

- `planned`
- `unknown`
- `not_applicable`
- `blocked`

Queries expose:

- `planned_count`
- `applicable_count`
- `attempted_count`
- `completed_count`
- `blocked_count`
- `changed_count`
- `clean_count`
- `not_applicable_count`
- `unknown_count`
- `regression_count`

Pass counts are never encoded as pass-specific columns.

## Run Values

`run_values` stores normalized value evidence from deterministic wrapper inputs:
pass-result markers, pass-result attributes, and cycle-finish status. It records
the value kind, optional class/key, typed value column, evidence source,
confidence, and links back to the cycle, file, and pass-run row when those
anchors exist.

This table is additive evidence, not a transcript scraper. Missing or malformed
markers are rejected or skipped as evidence while the underlying cycle or pass
recording continues under the existing validation rules. Path-oriented values
are anchored through `files`/`file_pass_runs` joins instead of being copied as
raw paths into the value text field.

The first normalized value kinds include pass outcomes, applicability, change
and regression status, validation commands/results, what changed, why it
mattered, findings, proof-needed notes, residual risk, cycle status, review
outcome, finish reason, and exit codes.

## Pass Result Markers

The prompt asks agents to include additive pass-result lines:

```text
UPKEEPER_PASS_RESULT: pass=P23 file=lib/upkeeper/example.bash applicable=1 outcome=clean changed=0 regression=0
UPKEEPER_PASS_RESULT: pass=P24 file=lib/upkeeper/example.bash applicable=1 outcome=fixed changed=1 regression=0
UPKEEPER_PASS_RESULT: pass=P25 file=lib/upkeeper/example.bash applicable=0 outcome=not_applicable changed=0 regression=0 reason=no_matching_surface
```

`UPKEEPER_STATUS` and `UPKEEPER_LOG_REVIEW` are unchanged. In normal runs,
missing `UPKEEPER_PASS_RESULT` lines remain additive-only and Lattice records
planned passes as `unknown` when it has enough planning context. When
`--prompt-pass=all` is active, incomplete or unavailable pass-result coverage
forces the cycle to `BLOCKED` before cleanup. Malformed lines are preserved as
rejected evidence and are never treated as clean results. Marker-looking text
inside Markdown code fences is ignored. Duplicate keys, missing `pass`, missing
`file`, and invalid pass codes are rejected. Future pass codes matching
`P[0-9A-Za-z_.-]+`, such as `P999`, do not need schema changes.

## Queries

Initial queries are:

```sh
tools/upkeeper_lattice.py query never-pass --pass P23
tools/upkeeper_lattice.py query pass-counts --path PATH
tools/upkeeper_lattice.py query file-history --path PATH
tools/upkeeper_lattice.py query regressions --path PATH
tools/upkeeper_lattice.py query least-reviewed
tools/upkeeper_lattice.py query most-fragile
tools/upkeeper_lattice.py query changed-since-last-pass --pass P23
tools/upkeeper_lattice.py query selection-candidates --mode oldest-mtime
tools/upkeeper_lattice.py query selection-candidates --mode max-cover
tools/upkeeper_lattice.py query explain-selection --cycle CYCLE_ID
tools/upkeeper_lattice.py query explain-selection --path PATH
tools/upkeeper_lattice.py query run-values --path PATH
tools/upkeeper_lattice.py query run-values --kind validation_command
tools/upkeeper_lattice.py query run-values --cycle CYCLE_ID
```

Formats:

- `--format text`
- `--format json`
- `--format jsonl`
- `--format tsv`

Coverage scopes:

- `current-eligible`
- `current-tracked`
- `known-active`
- `all-known`
- `deleted`
- `selected-history`

`never-pass` defaults to `current-eligible`. `least-reviewed` also defaults to
`current-eligible` and orders by completed pass count, completed cycle count,
oldest completed cycle, current mtime, and path. `most-fragile` uses score
version 1 and emits every score component. `changed-since-last-pass` treats a
file as changed when no completed pass exists, newer Git churn exists, or the
current worktree hash differs from the snapshot at the latest completed pass.

Optional Lattice selection modes can score historical facts, but final target
selection must still be revalidated against the current live source-safe
candidate boundary in the same cycle. The default
`UPKEEPER_LATTICE_SELECTION_MODE=oldest-mtime` preserves current-compatible
selection behavior.

`selection-candidates --mode max-cover` is the selection query used by
`./Upkeeper --max-cover` and `./FlameOn`. It ranks current tracked source-safe
text files by coverage pressure: first the oldest file with any unrun active
pass, then files with the lowest per-pass coverage count, then oldest mtime.
The query emits `score_json` with the active pass count, unrun pass count,
oldest unrun pass, and least-covered pass count. The wrapper still revalidates
the returned path against live local source-safety checks before launching
Codex.

## Regression Evidence

Regression events support confidence:

- `asserted`
- `inferred`
- `suspected`

Statuses are:

- `active`
- `retracted`
- `superseded`
- `disputed`

Manual regression marking is available with `mark-regression`.
`UPKEEPER_PASS_RESULT ... regression=1` records asserted regression evidence.
The schema supports `inferred` and `suspected` confidence for conservative
tool-failure reopen evidence, but Phase 1 does not treat that heuristic as
definitive. Reopened failure markers are imported and kept available for later
correlation; manual marks and pass-result `regression=1` lines are the validated
regression write paths. Corrections and retractions add rows instead of deleting
the original evidence.

## Import, Export, Backup, Recovery

`import-git` uses local Git as canonical when a clone is available. It imports
contributors, commits, file changes, renames, deletes, recreations, copies, and
shallow/incomplete state through import cursors. It uses NUL-safe Git output
where practical. Per-commit file-change rows are idempotent by repository,
commit, path, old path, and status, so an accidental rerun reports duplicates
without multiplying Git churn evidence. Normal `init` also removes duplicate
Git file-change rows left by older local databases before recreating the unique
guard index. Without `.git`, it reports unavailable with reason
`no_git_repository` and does not classify the condition as a DB failure.
Contributor identity now defaults to a stable SHA-256 token instead of stored
name/email PII, and commit rows store a subject hash plus subject length unless
`import-git --include-contributor-pii` or `import-git --include-commit-subjects`
is explicitly requested.

`import-upkeeper-log` reconstructs parseable cycle and preselection facts from
`Upkeeper.log`, including quoted fields such as `mode=--sandbox\ workspace-write`.

`import-change-notes` records annual release-note entries and explicit file
references when they are present.

`export-jsonl` writes portable JSONL under:

```text
runtime/upkeeper-lattice/exports/
```

Each exported row includes schema version, row type, row version, logical key,
source identity, repo identity, payload, payload SHA-256, and exported epoch.
Default exports now redact raw payload fields and path-bearing fields unless the
operator explicitly asks for disclosure with `--include-raw` and/or
`--include-paths`. Contributor fields remain redacted unless
`--include-contributors` is requested, and raw exports print a warning because
the JSONL may contain sensitive local evidence. Default exports also preserve
the Git-import privacy contract by omitting raw contributor fields and raw
commit subjects unless those values were explicitly included at import time.

Lattice export/import compatibility is governed by
`docs/compatibility.md`. Within a row version, `schema_version`, `row_type`,
`row_version`, `logical_key`, source identity, repo identity, payload,
`payload_sha256`, and exported epoch keep stable meanings. New optional payload
fields may be added, but import must remain idempotent for the same logical key
and payload hash, and different payloads for the same logical key must be
recorded as conflicts rather than overwritten silently.

If an operator needs a JSONL file for structural replay into another lattice
database, use `export-jsonl --include-paths`. The default redacted export is
safe for sharing and inspection, but it intentionally leaves path-bearing rows
too anonymized for full-fidelity file/cycle/history reconstruction.

Cycle-level provenance packages are a separate export surface tracked in
`docs/decisions/0005-provenance-and-evidence-package-exports.md`. The first
proposal is a local-only JSON evidence package emitted by `upkeeper
export-cycle --cycle-id X --format json`; future `--format ro-crate` or
`--format bagit` envelopes may wrap the same graph without changing its
provenance meaning.

Run taxonomy and cost-accounting summaries are a separate local surface
tracked in `docs/decisions/0006-run-taxonomy-observability-and-cost-accounting.md`.
The first proposal is a JSONL summary export emitted by `upkeeper
export-run-summary --cycle-id X --format jsonl`; future richer summary fields
may build on the same taxonomy and metric names without requiring a telemetry
daemon.

`import-jsonl` is idempotent. Same logical key and same payload hash is a
duplicate. Same logical key and a different payload hash records a conflict and
does not silently overwrite existing facts. Raw source lines stay redacted on
import by default; use `import-jsonl --preserve-raw` only when the destination
raw-storage mode is intentionally `full`.

`backup` uses SQLite backup support instead of blind-copying a live DB. Backups
default to:

```text
runtime/upkeeper-lattice/backups/
```

`recover` is local-only. It can rebuild from local Git history, live
`Upkeeper.log`, local failure markers, change notes, JSONL exports, and spooled
Lattice-unavailable recovery records. GitHub network reconciliation is Phase 2
and is not implemented in this phase.

## Prune

`prune` supports:

```sh
tools/upkeeper_lattice.py prune --older-than-days N
tools/upkeeper_lattice.py prune --raw-only
tools/upkeeper_lattice.py prune --transient-artifacts
tools/upkeeper_lattice.py prune --candidate-details
tools/upkeeper_lattice.py prune --vacuum
tools/upkeeper_lattice.py prune --dry-run
```

Prune does not delete core repo/file/cycle/pass/Git facts by default. Raw text
can be removed while parsed JSON, hashes, and source rows remain. Old candidate
details can be removed only for non-selected candidates and only when requested.
Import/export/recovery records are retained.

## Enterprise Scaling

The scale path is export/import/federation, not a central writable SQLite
database. A future aggregator may read JSONL exports or repository-local DB
snapshots, reconcile conflicts, and publish reports. Normal Upkeeper operation
does not assume a central server, network, daemon, or shared SQLite writer.

GitHub reconciliation is explicitly Phase 2. If implemented later, it must be
opt-in, must not store tokens in the DB, must use `GITHUB_TOKEN` or `gh auth`
only when explicitly requested, and must record GitHub facts as `source_records`
with `source_kind=github_api`. Local Git wins for file history when local Git
exists.
