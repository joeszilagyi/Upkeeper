# Negative-Space Testing

Negative-space testing is Upkeeper's explicit contract for behavior that must
not happen. Positive tests prove an allowed path works. Negative-space tests
prove a safety boundary stays closed when input, local state, backend output, or
operator configuration is malformed, hostile, stale, or merely inconvenient.

These fixtures are local and deterministic by default. They must not launch real
backend Codex, contact GitHub, read operator secrets, or depend on live runtime
state outside their temporary roots.

## Contract

When an Upkeeper change touches selection, config loading, backup, quota,
prompt compilation, status parsing, issue workflow, transcript handling,
evidence pruning, Lattice, or automation obligations, the patch should either
reuse an existing negative-space fixture from this catalog or add a new one.

Every serious security, data-integrity, custody, or automation-control bug fix
should leave at least one local proof for the corresponding "must not happen"
case. If a bug is fixed only by prose, the prose must explain why a deterministic
fixture is impossible or deferred.

## Serious Finding Repro Contract

A serious finding is any issue or PR that materially affects one of these
classes:

- security boundary
- filesystem writes/deletes
- Lattice import/export/recovery
- target selection
- quota/fallback behavior
- status marker parsing
- failure queue
- runtime cleanup
- cross-platform assumptions

Each serious finding must carry one of these before it is treated as closed:

- a local deterministic repro fixture that runs without backend Codex quota
- a cloud audit repro when the proof only makes sense in a clean or hosted
  environment
- an explicit documented non-repro rationale when reproduction would be unsafe,
  destructive, dependent on private data, or too expensive for the risk

The preferred local proof is the smallest test, validator fixture, parser
fixture, or stress-corpus case that would fail if the bug returned. New serious
finding issues should name the repro status in the issue body. PRs that fix
serious findings should name the fixture, cloud audit proof, or non-repro
rationale in the pull request body.

For serious issues opened before this template existed, the backfill rule is:
the issue or closing PR must gain the same repro status before closure. It can
name an existing local fixture, add a new fixture, point to a cloud audit proof,
or record a non-repro rationale. Release review treats missing repro status on
pre-existing serious issues as unfinished validation work, not as harmless
metadata debt.

## Baseline Invariants

| ID | Invariant | Current local proof |
| --- | --- | --- |
| NS-001 | Target selection must not select runtime artifacts, Git control files, ignored files, symlinks, or known sensitive local files. | `tools/validate_upkeeper.sh` selection guards, `tests/precontact_backup_test.bash` unsafe target rejection |
| NS-002 | Pre-contact backup and prompt compilation must not reveal the backup vault root, backup id, private age identity, or replacement authority to backend Codex. | `tests/precontact_backup_test.bash` prompt redaction and replacement-rule fixture |
| NS-003 | Backend Codex must not replace a selected target. If the selected target is impossible or unsafe, the backend must report a blocker and the wrapper must keep target authority. | `tests/precontact_backup_test.bash`, `docs/authority.md`, `docs/capability-profiles.md` |
| NS-004 | Bug-report-only, issue comment, issue review, and other read-only modes must not leave tracked-source mutations. | source mutation guard in `Upkeeper`, `tests/bug_report_only_test.bash`, issue workflow backend-mode validation |
| NS-005 | Malformed or decorated status, pass-result, session, quota, and runtime JSON markers must not be accepted as clean absence or successful work. | `tests/wrapper_contract_test.bash`, `tools/validate_upkeeper.sh` runtime parser checks |
| NS-006 | Local validation must not spend real backend quota or require live Codex sessions. | `tools/validate_upkeeper.sh` mode contract, fake backend fixtures, `.github/workflows/ci.yml` no-quota CI path |
| NS-007 | Shell-sourced config must not be treated as safe when the selected config path is missing, symlinked, wrong-owner, or group/world writable. | root `Upkeeper` config preflight and `tools/validate_upkeeper.sh` config-file support checks |
| NS-008 | Unsupported backend sandbox modes must not be accepted as active protection. | `tests/wrapper_contract_test.bash` CODEX mode rejection and allowlist fixtures |
| NS-009 | Control-plane inventory must count observed local state, not only expected launcher state, must flag tracked local-evidence artifacts such as root `$db`, `runtime/`, logs, transcripts, manifests, locks, and postmortems, and must allow only policy-listed safe cleanup before staging. Unknown local-evidence-like root artifacts and tracked evidence must block or enter obligation custody, with `KP-###` invariant ids and before/after snapshot deltas. | `docs/kirk-invariants.md`, `tools/upkeeper_control_plane_audit.py`, `tests/control_plane_audit_test.bash`, `tools/validate_upkeeper.sh --quick` |

## Updating The Catalog

Add a new row when a new class of "must not happen" behavior becomes
operationally important. Use stable IDs and point to the shortest local proof
that would fail if the boundary reopened. Keep broad stochastic fault injection
in `docs/fault-injection-scenarios.md`; keep this file focused on deterministic
contracts that are already enforceable or should be enforceable next.
