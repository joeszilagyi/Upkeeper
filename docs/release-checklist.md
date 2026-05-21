# Upkeeper Release Checklist

Use this checklist before treating `main` as a release-ready wrapper state.

## Source State

- `main` is clean and synced with `origin/main`.
- Open feature branches or backlog PRs are either merged, intentionally left
  open, or documented as out of scope for the release.
- No `runtime/`, `Upkeeper.log`, transcripts, local manifests, locks, Codex
  session files, or other machine-local evidence is staged.
- The current year's `change_notes_YYYY.md` has entries for notable
  operator-facing changes.

## Validation

Run the applicable local checks from the central checkout:

```sh
tools/validate_upkeeper.sh --deps
bash -n Upkeeper lib/upkeeper/*.bash tools/*.sh tests/*.bash testruns/*.sh Upkeeper.conf configurations/default.conf
set -e; for test_script in tests/*.bash; do bash "$test_script"; done
tools/check_public_docs.sh --quick
tools/validate_upkeeper.sh --quick
tools/validate_upkeeper.sh --full
git diff --check
```

## Issue Triage Taxonomy and Release Gate

- Current issue priority order is the repository default `security > data-integrity > bug`,
  exposed by `UPKEEPER_ISSUE_PRIORITY_LABELS` and used by `--fix-next-issue` / `--fix-oldest-bug`.
- Use this local taxonomy fallback when GitHub labels are intentionally minimal:
  - `p0-release-blocker` (must gate release; use `security` when no dedicated labels exist)
  - `p1-trust` (use `security` when no dedicated labels exist)
  - `p1-validation` (use `security` when no dedicated labels exist)
  - `p1-safety` (use `security` when no dedicated labels exist)
  - `p1-docs` (use `security` or `data-integrity` when no dedicated labels exist)
  - `p2-ux` (use `bug` when no dedicated labels exist)
  - `p2-portability` (use `bug` when no dedicated labels exist)
  - `p2-prompt` (use `bug` when no dedicated labels exist)
  - `p3-polish` (use `bug` when no dedicated labels exist)
- A safe release must complete a no real Codex backend validation gate in this
  order:
  1. `tools/validate_upkeeper.sh --deps`
  2. `tools/validate_upkeeper.sh --quick`
  3. `tools/validate_upkeeper.sh --full`
  4. `tools/check_public_docs.sh --quick`
  5. `tools/stress_upkeeper_corpus.sh --local`
- Release prep must also include compatibility/operator-doc updates when any
  operator-visible behavior, prompt contracts, docs, config profiles, or issue
  triage behavior changes.

Docs-only releases may use the cheaper docs path when no runtime, tool, config,
prompt, test, or launcher behavior changed:

```sh
tools/check_public_docs.sh --quick
tools/validate_upkeeper.sh --smoke
git diff --check
```

## Documentation

- README links to the relevant operator, compatibility, security, dependency,
  release-readiness, and prompt docs.
- `docs/compatibility.md` still describes the public operator-visible surface.
- `docs/security.md` still describes local trust and evidence boundaries.
- `docs/dependencies.md` still matches validator and runtime dependency checks.
- `docs/known-issues.md` lists the major unresolved release risks.

## Merge And Cleanup

- PR CI is green before merge.
- Merge commits mention operator-facing impact when behavior changes.
- After merge, verify local `main` is clean and synced with `origin/main`.
- Delete merged feature branches and prune stale remotes.
