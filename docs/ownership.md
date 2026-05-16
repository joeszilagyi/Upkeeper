# Upkeeper Ownership

Upkeeper is maintainer-led. This document defines responsibility areas so future
automation and reviews can route decisions without relying on private context.

## Role Model

- Accountable maintainer: owns final product, safety, compatibility, and release
  decisions.
- Implementer: prepares patches, tests, docs, and PR bodies within the tracked
  contracts.
- Reviewer: checks behavior, risk, validation, public docs, and compatibility
  before merge.
- Operator: runs local loops, watches machine-health blocks, and keeps
  machine-local secrets out of tracked source.

One person may hold multiple roles, but the responsibilities remain distinct.

## Responsibility Areas

| Area | Accountable | Review focus |
| --- | --- | --- |
| Product behavior | Accountable maintainer | Operator outcome, no-op behavior, failure clarity |
| Shell architecture | Accountable maintainer | Bash compatibility, load order, safe sourcing |
| Prompts and review modules | Accountable maintainer | Applicability gates, numbering compatibility, public wording |
| Public docs | Accountable maintainer | Completeness, clarity, no private chat dependency |
| Validation | Accountable maintainer | No-quota default, deterministic checks, useful failure text |
| Security and privacy | Accountable maintainer | Local trust boundaries, evidence handling, safe defaults |
| Compatibility | Accountable maintainer | Preserved operator surface or documented migration path |
| Releases | Accountable maintainer | Release checklist, known issues, CI, branch cleanup |

## Escalation Rules

- Machine health and local safety outrank workload progress.
- Compatibility breaks require same-patch documentation of reason, impact, and
  migration path.
- Public behavior changes need README/operator docs or compatibility docs when
  the change affects how an operator invokes, trusts, or interprets Upkeeper.
- Runtime evidence, local manifests, logs, transcripts, and machine-local config
  are not source ownership surfaces.
