# Upkeeper Policy Decisions

Upkeeper policy decisions are small JSON records for local control-plane
choices that must not depend only on prompt prose. They are intended for
wrapper-side decisions such as whether a run may contact backend Codex, write
tracked source, retarget work, restore backups, use network tools, or file an
issue.

The first implementation is deliberately small. It provides a schema-v1 shape
and a shell helper in `lib/upkeeper/policy_decisions.bash` that can emit and
validate records with existing `jq`. It does not add a new policy engine,
service, or external dependency.

## Schema Version 1

Every decision record must be a JSON object with these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `schema_version` | number | Current stable value is `1`. |
| `decision_id` | string | Stable local id for the decision point. |
| `capability_profile` | string | One profile from `docs/capability-profiles.md`. |
| `mode` | string | The current wrapper mode or launcher phase. |
| `selected_target` | string | Selected target path or `none` when no file target exists. |
| `may_contact_backend` | boolean | Whether the next step may launch backend Codex. |
| `may_write_source` | boolean | Whether source-file mutations are allowed. |
| `may_retarget` | boolean | Whether the task may replace the selected target. |
| `may_restore_backup` | boolean | Whether backup restoration is allowed. |
| `may_use_network` | boolean | Whether the actor may use network tools. |
| `may_file_issue` | boolean | Whether the actor may create or update GitHub issues. |
| `allowed_writes` | string array | Bounded write targets, or an empty array for none. |
| `denied_actions` | string array | Machine-readable action ids that are blocked. |
| `reasons` | string array | Non-empty local reasons supporting the decision. |
| `evidence` | string array | Optional local evidence identifiers or log markers. |

Policy records are local evidence. They may be logged, stored in ignored
runtime state, or attached to later Lattice evidence, but tracked source should
not depend on unversioned policy records as the sole authority for a safety
claim.

## Known Capability Profiles

Schema-v1 validation accepts these profile ids:

- `operator`
- `wrapper-local-control-plane`
- `backend-codex-default-review`
- `backend-codex-bug-report-only`
- `backend-codex-issue-comment`
- `backend-codex-issue-review`
- `backend-codex-issue-apply`
- `fallback-postmortem-backend`
- `lattice-cli`
- `local-validation-ci`

The profile names intentionally mirror `docs/capability-profiles.md`, but use
stable lowercase ids for JSON.

## Helper Contract

`lib/upkeeper/policy_decisions.bash` owns the local helper functions:

- `upkeeper_policy_decision_schema_version`
- `upkeeper_policy_decision_profile_is_known PROFILE`
- `upkeeper_policy_decision_validate_json JSON`
- `upkeeper_policy_decision_emit ...`

The emitter is a convenience for shell callers that already have scalar
decision fields. It accepts comma-separated lists for `allowed_writes`,
`denied_actions`, `reasons`, and optional `evidence`. Commas inside individual
list values are not supported by the emitter. Callers that need richer strings
should build JSON directly and then call
`upkeeper_policy_decision_validate_json`.

Example:

```sh
source lib/upkeeper/policy_decisions.bash

upkeeper_policy_decision_emit \
  selected-target-precontact \
  wrapper-local-control-plane \
  precontact \
  tools/example.py \
  true \
  true \
  false \
  false \
  false \
  false \
  tools/example.py \
  retarget,restore_backup,file_issue \
  selected_target_backed_up,quota_guardrail_allowed \
  Upkeeper.log
```

## Compatibility Rules

Schema-v1 fields are stable. A future schema may add optional fields, but it
must not silently change the meaning or type of existing fields. Removing or
renaming a field requires a new schema version, compatibility notes, and local
validation updates.

Policy decisions are not a substitute for enforcement. A policy record explains
what the wrapper decided; the relevant runtime module still has to enforce the
decision. When a patch changes who may select targets, write source, run shell,
spend quota, restore backups, prune evidence, affect GitHub, modify Lattice, or
read runtime evidence, update `docs/control-ledger.md` and keep validation
coverage in the same branch.
