# Upkeeper Authority Model

Upkeeper is a local control plane. It owns the wrapper-side decisions that make
an unattended Codex cycle safe enough to start: configuration, target selection,
backup, quota checks, local evidence, issue handoff, and final validation.

Backend Codex is a task worker inside the wrapper-built airlock. It may inspect
the selected context, run allowed local commands through the configured sandbox,
and return a patch or report. It does not own target replacement, GitHub
credentials, quota guardrails, evidence pruning, or final custody decisions.

The operator owns the machine, credentials, config files, secrets, and final
release decisions. Upkeeper can make local guardrail decisions, but it does not
turn untrusted local state into trusted state merely because a model said it was
safe.

## Authority Questions

| Question | Authority holder | Current rule |
| --- | --- | --- |
| Who may select a target? | Wrapper local control plane | Normal selection is deterministic before backend launch. Explicit `--target-file` remains the strongest safe one-cycle pin. |
| Who may replace a target? | Wrapper local control plane | Backend Codex must report `BLOCKED` when the selected target is impossible or unsafe; it must not pick a replacement target for the same cycle. |
| Who may write source? | Wrapper plus selected backend stage | Dry-run, comment, review, and bug-report-only modes are source read-only. Apply/default fix stages may write through the configured Codex sandbox. |
| Who may run shell? | Wrapper and sandboxed backend Codex | The wrapper runs local preflight and validation commands. Backend Codex runs commands only through `codex exec` with the configured sandbox and wrapper-supplied environment. |
| Who may spend model quota? | Wrapper local control plane | Quota preflight and cooldown markers decide whether a backend call may start. Validation paths must stay no-quota by default. |
| Who may restore backups? | Operator | Upkeeper creates selected-target pre-contact backups; restore is a deliberate operator action and private age identities stay out of prompts and tracked config. |
| Who may prune evidence? | Wrapper local control plane | Pruning is allowed only for wrapper-owned, permission-checked, machine-local evidence paths. Runtime evidence is not source. |
| Who may file or close issues? | Wrapper broker plus operator policy | Issue workflows fetch and post through wrapper-brokered GitHub calls. Backend Codex does not inherit GitHub tokens or direct network tools. |
| Who may modify Lattice? | Wrapper local control plane and Lattice CLI | Lattice records additive local evidence. It does not replace Git or live source-safe eligibility. |
| Who may read secrets or runtime evidence? | Operator and wrapper-local checks | Runtime evidence and `$CODEX_HOME` are private local state. Backend prompts receive bounded task packets, not arbitrary secret or session material. |

## Lifecycle Points

### Startup And Config

The wrapper resolves the central checkout, loads trusted local config, and
normalizes defaults before any backend work. Config files are shell-sourced
trusted local input. They are not safe to load from untrusted issue bodies,
shared writable directories, downloads, or client-generated artifacts.

### Selection And Backup

Target authority belongs to the wrapper. Selection starts from live local files,
Git status, ignore rules, `.upkeeperignore`, explicit target pins, failure
queues, startup anomaly gates, and Lattice hints when enabled. Before the prompt
grants selected-target authority, Upkeeper creates the configured pre-contact
backup when required.

### Backend Airlock

The backend receives the wrapper-built prompt, selected target context,
configured sandbox, and bounded environment. The backend can propose or perform
work inside that boundary, but the wrapper remains responsible for final status
classification, obligation creation, issue side effects, and merge readiness.

### Issue Workflows

ChimneySweep and related issue-fix flows rank and fetch issue evidence before
backend launch. Comment and review stages are source read-only. Apply stages may
write source, but GitHub I/O remains wrapper-brokered and direct backend network
tools are shadowed.

### Adapters And Integrations

Future selector, backup, sandbox, exporter, tracker, feed, validator, and
reporter adapters are bounded wrapper integrations, not free-form shell
extensions. `docs/decisions/0007-adapter-plugin-contract-with-side-effect-declarations.md`
defines the required declared inputs, outputs, side effects, network use,
file-write scope, secret needs, Lattice events, failure modes, and validation
expectations for those integrations.

### Evidence And Lattice

Logs, transcripts, Lattice rows, obligations, failure markers, manifests,
postmortems, and wrapper health state are local evidence. They help future runs
explain and repair work, but they do not override live Git state or source-safe
eligibility without a documented control.

### Run Transactions

Every cycle is a transaction with prepare, select target, snapshot/backup,
launch backend, capture side effects, classify diff/output, verify, resolve,
and record stages. `docs/decisions/0004-run-transaction-contracts.md` defines
the commit, rollback, replay, and verification vocabulary for that lifecycle.

### Validation And Release

Validation entrypoints are deterministic and no-quota by default. They may run
dry-runs, parser checks, fake Codex fixtures, and local stress corpus paths, but
they must not launch real backend Codex unless an operator explicitly requests a
backend-specific run. Validation-owned child Upkeeper dry-runs isolate
themselves from live operator quota cooldown markers; quota guardrail behavior is
covered only by explicit quota fixtures.

## Reading Map

- `docs/capability-profiles.md` lists capabilities by actor and mode.
- `docs/control-ledger.md` maps named controls to enforcement points, tests,
  evidence artifacts, and status.
- `docs/policy-decisions.md` defines the schema for local authority decisions
  that should be recorded as data instead of prompt prose.
- `docs/decisions/0007-adapter-plugin-contract-with-side-effect-declarations.md`
  defines the side-effect declaration contract for future adapter and plugin
  integrations.
- `docs/decisions/0004-run-transaction-contracts.md` defines the bounded
  transaction vocabulary for cycle explanation, replay, rollback, and
  verification.
- `docs/decisions/0003-schema-gated-airlocks.md` defines the typed-signal
  airlock pattern for raw evidence that may cross into wrapper authority.
- `docs/security.md` describes local trust boundaries and secret handling.
- `docs/compatibility.md` describes the stable public feature surface.
