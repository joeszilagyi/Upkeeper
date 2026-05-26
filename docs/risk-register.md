# Upkeeper Risk Register

This register summarizes high-impact risks that affect release readiness or
operator trust. GitHub issues remain the detailed work tracker.

| Risk | Impact | Current mitigation | Status |
| --- | --- | --- | --- |
| Untrusted shell-sourced config | Arbitrary local command execution if operators source hostile config | Config is documented as trusted local input only; machine-local env is separate from tracked config | Open |
| Stale client wrapper copies | Client repos may miss central safety fixes | Central-first symlink model is documented; client tracked wrapper churn is discouraged | Open |
| Real backend work during validation | Validation could spend quota or mutate through a model unexpectedly | CI/local validation use dry-runs, fake Codex, parser fixtures, and local corpus mode | Mitigated |
| Committed runtime evidence | Logs, transcripts, manifests, locks, or local state could leak private evidence | `.gitignore`, docs, and agent contract classify runtime evidence as local only | Mitigated |
| Fallback/postmortem boundary drift | Recovery flows could act on wrong workload or unsafe artifacts | Fallback contracts, postmortem docs, and validation cover selected-target and safety boundaries | Open |
| Quota snapshot misinterpretation | Local session evidence could be stale or misread, causing bad stop/defer choices | Quota guardrails are advisory and log snapshot identity/age; validation covers parser contracts | Open |
| Lattice integrity blockers | Evidence ledger could misattribute or corrupt state if treated as authority too soon | Known issues and roadmap warn not to treat Lattice as sole custody authority yet | Open |
| Parallel worker collisions | Multiple automation workers could contend for a checkout or PR | Active-lock and backlog ownership checks serialize one checkout; parallel work needs isolated worktrees | Open |
| Threat/degraded-mode doctrine drift | Operators could misunderstand whether a safety block is covered, degraded, overridable, or out of scope | `docs/security.md` now tracks threat coverage, degraded-mode behavior, and override rules; quick validation checks the required doctrine terms | Mitigated |
| Evidence preservation drift | Logs, transcripts, backups, Lattice rows, exports, and recovery artifacts could be kept, pruned, or published with inconsistent privacy assumptions | `docs/preservation-policy.md` defines evidence temperature, artifact privacy classes, and promotion rules; quick validation checks the required policy terms | Mitigated |
| Source rights drift | OSINT or citation material could be prompted, exported, archived, quoted, uploaded, or used in public evidence without a consistent rights review | `docs/source-rights-metadata.md` defines source sensitivity labels and rights fields; quick validation checks the required policy terms | Mitigated |

## Maintenance

Update this file when a risk changes status, mitigation, or release impact. Do
not list every bug; record risks that future operators or release reviewers need
to understand before trusting an unattended run.
