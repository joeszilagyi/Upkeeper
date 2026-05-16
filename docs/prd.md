# Upkeeper Product Requirements

Upkeeper is a local maintenance wrapper for running bounded Codex reviews
against this repository and symlinked client repositories. It is not a hosted
service, daemon, package manager, or custody authority.

## Product Goal

Provide a repeatable, no-surprises way to select local maintenance targets,
package the correct prompt/context, run Codex only when explicitly allowed,
capture evidence, and stop safely when machine health, quota, trust, or
validation boundaries are not satisfied.

## Primary Users

- Maintainer running Upkeeper directly in the central checkout.
- Maintainer running Upkeeper through a symlinked client checkout.
- Automation loop operator watching backlog or burn-cycle progress locally.
- Future reviewer trying to understand whether a change is release-ready from
  tracked source alone.

## Required Capabilities

- Deterministic target selection before backend execution.
- Explicit one-cycle overrides for target files, config, prompt passes, review
  modules, and issue-workflow stages.
- No-quota validation modes for local edit loops and CI.
- Clear operator output for health blocks, quota deferrals, selected targets,
  and completed work.
- Private local evidence handling for logs, transcripts, runtime state, and
  machine-local config.
- Symlinked client behavior that keeps wrapper source centralized.
- Public documentation for compatibility, security, dependencies, release
  readiness, and known limitations.

## Non-Goals

- Replacing project-specific tests or CI.
- Running as an always-on service.
- Trusting model-written runtime evidence as an authority without validation.
- Publishing local runtime artifacts by default.
- Supporting arbitrary shell families before the Bash implementation has a
  tracked migration plan.

## Release Readiness

A release-ready state must satisfy the release checklist, keep known issues
visible, and preserve the compatibility contract unless the same change
documents an unavoidable compatibility break and migration path.
