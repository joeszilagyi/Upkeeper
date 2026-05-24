# Upkeeper Capability Profiles

This file is the tracked capability manifest for Upkeeper's local control plane.
It describes which actor or mode may perform sensitive actions. The control
ledger in `docs/control-ledger.md` names the checks that make these claims
testable. `docs/policy-decisions.md` defines the stable lowercase profile ids
used when these claims are recorded as structured JSON policy decisions.

## Capability Legend

- `yes`: allowed by design in that profile.
- `no`: not allowed by design.
- `brokered`: allowed only through a wrapper-owned broker or staged handoff.
- `local-only`: allowed only for local machine evidence, not tracked source or
  remote services.
- `operator`: reserved for a deliberate operator action.

## Profiles

| Profile | Select target | Replace target | Write source | Run shell | Spend model quota | Restore backup | Prune evidence | File or close issues | Modify Lattice | Read secrets/runtime evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Operator | yes | yes | yes | yes | yes | operator | operator | yes | yes | yes |
| Wrapper local control plane | yes | yes | local-only | yes | yes | no | local-only | brokered | yes | local-only |
| Backend Codex default review | no | no | yes | yes | yes | no | no | no | no | selected context only |
| Backend Codex bug-report-only | no | no | no | yes | yes | no | no | no | no | selected context only |
| Backend Codex issue comment stage | no | no | no | yes | yes | no | no | no | no | issue packet plus selected context |
| Backend Codex issue review stage | no | no | no | yes | yes | no | no | no | no | issue packet plus selected context |
| Backend Codex issue apply stage | no | no | yes | yes | yes | no | no | no | no | issue packet plus selected context |
| Fallback or postmortem backend | no | no | bounded | yes | yes | no | no | no | no | incident packet plus selected context |
| Lattice CLI | no | no | no | local-only | no | no | local-only | no | yes | local runtime evidence |
| Local validation and CI | no | no | fixture-only | yes | no | no | fixture-only | no | fixture-only | fixtures and local repo |

## Stable Policy Profile Ids

When Upkeeper records a schema-v1 policy decision, the `capability_profile`
field uses one of these ids:

| Human profile | Policy id |
| --- | --- |
| Operator | `operator` |
| Wrapper local control plane | `wrapper-local-control-plane` |
| Backend Codex default review | `backend-codex-default-review` |
| Backend Codex bug-report-only | `backend-codex-bug-report-only` |
| Backend Codex issue comment stage | `backend-codex-issue-comment` |
| Backend Codex issue review stage | `backend-codex-issue-review` |
| Backend Codex issue apply stage | `backend-codex-issue-apply` |
| Fallback or postmortem backend | `fallback-postmortem-backend` |
| Lattice CLI | `lattice-cli` |
| Local validation and CI | `local-validation-ci` |

## Notes By Capability

### Target Selection

Target selection is a wrapper capability. Lattice, manifests, mtime ordering,
failure queues, issue inference, startup anomaly gates, and explicit
`--target-file` pins can all influence wrapper selection, but the backend model
does not get to redirect the cycle to a new file after launch.

### Source Writes

Source writes depend on mode. Default repair and issue apply stages can write
source through the configured Codex sandbox. Dry-run, bug-report-only, issue
comment, and issue review stages must not leave tracked-source mutations.

### Shell Execution

The wrapper uses shell commands for local control-plane work. Backend Codex
uses the configured `codex exec` sandbox. Validation may run shell fixtures and
dry-runs, but no validation mode launches real backend Codex by default.

### Quota Spend

The wrapper decides whether quota can be spent before a backend call starts.
Backend Codex consumes quota only after the wrapper has selected the task,
checked local health, and passed quota guardrails or an explicit launcher
bypass policy.

### Backup Restore

Upkeeper creates selected-target backups before backend contact, but restore is
an operator action. The private age identity belongs outside tracked config,
prompts, and backend environments.

### Evidence Pruning

Evidence pruning is local-only and path-checked. The wrapper may rotate or
prune evidence only for paths it owns and has validated. Backend Codex should
not delete transcripts, logs, obligations, quota snapshots, or Lattice state.

### Issue Effects

GitHub issue effects are wrapper-brokered. The backend may draft comments or
summaries in an agreed return channel; the wrapper owns token handling, direct
GitHub commands, and final posting policy.

### Lattice Writes

Lattice writes are additive evidence. Lattice can improve explanation,
selection intelligence, and recovery, but live source-safe eligibility and Git
state remain authoritative unless a future control explicitly changes that.
