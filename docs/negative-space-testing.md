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

## Updating The Catalog

Add a new row when a new class of "must not happen" behavior becomes
operationally important. Use stable IDs and point to the shortest local proof
that would fail if the boundary reopened. Keep broad stochastic fault injection
in `docs/fault-injection-scenarios.md`; keep this file focused on deterministic
contracts that are already enforceable or should be enforceable next.
