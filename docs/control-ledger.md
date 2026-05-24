# Upkeeper Control Ledger

This ledger maps safety and authority claims to enforcement points, tests, and
evidence. It is not a runtime database. It is the tracked source that tells a
maintainer which local control proves which authority boundary.

Status values:

- `active`: implemented and covered by local validation or tests.
- `partial`: implemented in part, with known follow-up work.
- `documented`: documented contract that still needs stronger local checks.

| Control id | Claim | Enforcement point | Validation or test | Evidence artifacts | Status |
| --- | --- | --- | --- | --- | --- |
| AUTH-001 | Target selection is wrapper-owned before backend launch. | `lib/upkeeper/help_selection.bash`, `lib/upkeeper/file_manifest.bash`, issue-target handoff in `lib/upkeeper/codex_io.bash` | `tools/validate_upkeeper.sh --quick`, target-selection full checks | `Upkeeper.log` selection lines, manifest state, Lattice preselect evidence | active |
| AUTH-002 | Backend Codex cannot choose an unbacked replacement target in the same cycle. | Default prompt selected-target contract, review summary parser, explicit target mismatch handling | `tools/validate_upkeeper.sh --quick`, `tests/lattice_test.bash` cycle-finish mismatch fixture | final review summary, `target_substitution_rejected`, cycle exit reason | active |
| AUTH-003 | Required selected-target backup happens before backend contact. | `lib/upkeeper/precontact_backup.bash`, prompt compile order in `Upkeeper` | `tests/precontact_backup_test.bash`, full validation dry-runs | backup sidecar, redacted backup log fields, `codex_exec_started=0` on failure | active |
| AUTH-004 | Unsafe backend sandbox modes are rejected. | `validate_codex_mode_args_or_exit` in `lib/upkeeper/codex_io.bash` | `tests/wrapper_contract_test.bash` | startup rejection output, no backend transcript | active |
| AUTH-005 | Validation and CI stay no-quota by default. | CI workflow, `UPKEEPER_DRY_RUN=1`, fake Codex fixtures, validation harness | `tools/validate_upkeeper.sh --quick`, `.github/workflows/ci.yml` checks | CI logs, dry-run cycle exits, fake Codex transcripts | active |
| AUTH-006 | Issue GitHub effects are wrapper-brokered, not backend-direct. | ChimneySweep issue workflow, backend environment token stripping, command shadowing | `tools/validate_upkeeper.sh --quick`, ChimneySweep tests | issue packet logs, proposed comment blocks, wrapper-posted comments | active |
| AUTH-007 | Comment and review issue stages are source read-only. | Issue workflow stage policy and source fingerprints | `tools/validate_upkeeper.sh --quick`, workflow stage fixtures | before/after source fingerprints, stage logs | active |
| AUTH-008 | Runtime evidence is local state, not source. | `.gitignore`, docs, runtime path guards, artifact permission checks | `tools/validate_upkeeper.sh --quick`, public docs checks | ignored `runtime/`, transcripts, obligations, postmortems, logs | active |
| AUTH-009 | Evidence pruning is limited to wrapper-owned safe paths. | log rotation guards, transcript artifact guards, active-lock cleanup guards | `tools/validate_upkeeper.sh --quick`, transcript and log-path tests | prune-blocked warnings, quarantine records, rotation markers | active |
| AUTH-010 | Lattice is additive evidence and not sole custody authority. | `lib/upkeeper/lattice.bash`, `tools/upkeeper_lattice.py`, `docs/known-issues.md` | `tests/lattice_test.bash`, `tools/validate_upkeeper.sh --quick` | SQLite rows, recovery JSONL, degraded-mode warning records | active |
| AUTH-011 | Machine health and obligations outrank new workload. | backlog obligation reconciliation and startup anomaly custody | `tools/validate_upkeeper.sh --quick`, obligation and anomaly custody checks | obligation JSON, issue-ready reports, backlog log custody summaries | active |
| AUTH-012 | Shell-sourced config is trusted local input only. | config path trust checks and public docs | `tools/validate_upkeeper.sh --quick`, config-file support checks | config load logs, config source hash, explicit config failures | active |

## Maintenance Rule

When a patch changes who can select targets, write source, run shell, spend
quota, restore backups, prune evidence, affect GitHub, modify Lattice, or read
runtime evidence, update this ledger in the same branch. If the claim is
deterministic enough to check locally, add or update validation before marking
the control `active`.
