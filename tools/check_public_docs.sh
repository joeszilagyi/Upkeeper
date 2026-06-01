#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

log() {
  printf 'check_public_docs: %s\n' "$*" >&2
}

fail() {
  printf 'check_public_docs: ERROR: %s\n' "$*" >&2
  exit 1
}

case "${1:-}" in
  ""|--quick)
    ;;
  --help|-h)
    cat <<'EOF'
Usage: tools/check_public_docs.sh [--quick]

Checks deterministic parts of Upkeeper's public documentation policy:
version/doc sync, required review-module policy wiring, broken repo-local
Markdown links, and obvious placeholder/legalese public text.
EOF
    exit 0
    ;;
  *)
    fail "unknown argument: $1"
    ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  fail "not a Git worktree: $ROOT_DIR"

mapfile -t public_text_files < <(
  git ls-files --cached --others --exclude-standard \
    AGENTS.md \
    PLANS.md \
    README.md \
    Upkeeper.conf \
    .upkeeperignore \
    'change_notes_[0-9][0-9][0-9][0-9].md' \
    'configurations/*.conf' \
    '.github/workflows/*.yml' \
    'docs/*.md' \
    'docs/scripts/*.md' \
    'lib/upkeeper/README.md' \
    'prompts/*.md' \
    'templates/*.md' \
    Upkeeper \
    FlameOn \
    ChimneySweep \
    'completions/*.bash' \
    'lib/upkeeper/*.bash' \
    'tools/*.sh' \
    | sort -u
)

[[ "${#public_text_files[@]}" -gt 0 ]] || fail "no public text files found"

wrapper_version="$(sed -n 's/^UPKEEPER_VERSION="\([^"]*\)"/\1/p' Upkeeper | head -n 1)"
header_version="$(sed -n 's/^## Version: \(v[0-9][^[:space:]]*\)$/\1/p' Upkeeper | head -n 1)"
release_notes_file="change_notes_$(date +%Y).md"
[[ -n "$wrapper_version" ]] || fail "could not read UPKEEPER_VERSION"
[[ "$header_version" == "$wrapper_version" ]] || fail "Upkeeper header version $header_version does not match $wrapper_version"
[[ ! -e change_notes.md ]] || fail "use annual change_notes_YYYY.md release-note files, not change_notes.md"
[[ -s "$release_notes_file" ]] || fail "$release_notes_file is missing or empty"
[[ -s contracts/public_docs.tsv ]] || fail "public docs contract manifest is missing or empty"

tools/check_contract_manifest.py --root "$ROOT_DIR" contracts/public_docs.tsv >/dev/null ||
  fail "public docs contract manifest failed"

grep -Fq "Version: $wrapper_version" docs/scripts/upkeeper.md || fail "operator guide is not current with $wrapper_version"
grep -Fq "$wrapper_version changes" "$release_notes_file" || fail "$release_notes_file has no entry for $wrapper_version"

[[ -s docs/public-documentation-policy.md ]] || fail "public documentation policy is missing or empty"
[[ -s docs/security.md ]] || fail "security trust model is missing or empty"
[[ -s docs/preservation-policy.md ]] || fail "preservation policy is missing or empty"
[[ -s docs/source-rights-metadata.md ]] || fail "source rights metadata policy is missing or empty"
[[ -s .upkeeperignore ]] || fail ".upkeeperignore is missing or empty"
[[ -s LICENSE ]] || fail "LICENSE is missing or empty"
[[ -s prompts/p26-public-documentation-review.md ]] || fail "P26 review module prompt is missing or empty"
[[ -s prompts/p27-educational-debrief-review.md ]] || fail "P27 review module prompt is missing or empty"
[[ -s prompts/p28-unit-test-harvesting-review.md ]] || fail "P28 review module prompt is missing or empty"
[[ -s prompts/p29-reuse-harvesting-review.md ]] || fail "P29 review module prompt is missing or empty"
[[ -s prompts/p30-stark-protocol-review.md ]] || fail "P30 review module prompt is missing or empty"
grep -Fq "P27 After-Action Review:" prompts/p27-educational-debrief-review.md || fail "P27 saved after-action structure missing"
grep -Fq "# P29 Reuse Harvesting Review" prompts/p29-reuse-harvesting-review.md || fail "P29 prompt title missing"
grep -Fq "P29: not applicable" prompts/p29-reuse-harvesting-review.md || fail "P29 applicability line missing"
grep -Fq "Shell Reuse Safety Gates" prompts/p29-reuse-harvesting-review.md || fail "P29 shell safety gates missing"
grep -Fq "Reuse Debt Output" prompts/p29-reuse-harvesting-review.md || fail "P29 reuse debt output missing"
grep -Fq "# P30 Stark Protocol Review" prompts/p30-stark-protocol-review.md || fail "P30 prompt title missing"
grep -Fq "P30: not applicable" prompts/p30-stark-protocol-review.md || fail "P30 applicability line missing"
grep -Fq "same weakness cannot get us twice" prompts/p30-stark-protocol-review.md || fail "P30 same-weakness rule missing"
grep -Fq "Non-regression evidence" prompts/p30-stark-protocol-review.md || fail "P30 non-regression evidence output missing"
grep -Fq "Reusable Asset Ownership" lib/upkeeper/README.md || fail "module README missing reusable asset ownership map"
grep -Fq ".upkeeperignore" README.md || fail "README missing .upkeeperignore selection-firewall docs"
grep -Fq ".upkeeperignore" docs/scripts/upkeeper.md || fail "operator guide missing .upkeeperignore docs"
grep -Fq ".upkeeperignore" docs/compatibility.md || fail "compatibility docs missing .upkeeperignore contract"
grep -Fq ".upkeeperignore" docs/security.md || fail "security docs missing .upkeeperignore boundary"
grep -Fq "public project material" docs/public-documentation-policy.md || fail "public documentation policy missing public-by-default rule"
grep -Fq "tools/check_public_docs.sh" docs/public-documentation-policy.md || fail "public documentation policy missing tool reference"
grep -Fq "docs/public-documentation-policy.md" README.md || fail "README does not link the public documentation policy"
grep -Fq "docs/security.md" README.md || fail "README does not link the security trust model"
grep -Fq "docs/preservation-policy.md" README.md || fail "README does not link the preservation policy"
grep -Fq "docs/source-rights-metadata.md" README.md || fail "README does not link source rights metadata"
grep -Fq "docs/policy-decisions.md" README.md || fail "README does not link policy decisions"
grep -Fq "docs/security.md" docs/public-documentation-policy.md || fail "public documentation policy does not link the security trust model"
grep -Fq "docs/policy-decisions.md" docs/authority.md || fail "authority model does not link policy decisions"
grep -Fq "docs/policy-decisions.md" docs/security.md || fail "security trust model does not link policy decisions"
grep -Fq "schema_version" docs/policy-decisions.md || fail "policy decisions doc missing schema_version"
grep -Fq "may_contact_backend" docs/policy-decisions.md || fail "policy decisions doc missing may_contact_backend"
grep -Fq "denied_actions" docs/policy-decisions.md || fail "policy decisions doc missing denied_actions"
grep -Fq "## Compatibility Classes" docs/compatibility.md || fail "compatibility docs missing compatibility classes"
grep -Fq '`stable`' docs/compatibility.md || fail "compatibility docs missing stable class"
grep -Fq '`experimental`' docs/compatibility.md || fail "compatibility docs missing experimental class"
grep -Fq '`deprecated`' docs/compatibility.md || fail "compatibility docs missing deprecated class"
grep -Fq '`removed`' docs/compatibility.md || fail "compatibility docs missing removed class"
grep -Fq "## Lattice Import/Export Compatibility" docs/compatibility.md || fail "compatibility docs missing Lattice import/export rules"
grep -Fq "Lattice export/import compatibility is governed by" docs/lattice.md || fail "Lattice docs missing compatibility pointer"
grep -Fq "Shell-Sourced Config Files" docs/security.md || fail "security trust model missing config-file coverage"
grep -Fq "Codex Sandbox Mode" docs/security.md || fail "security trust model missing sandbox coverage"
grep -Fq "CODEX_HOME Session Parsing" docs/security.md || fail "security trust model missing CODEX_HOME coverage"
grep -Fq "## Threat Model" docs/security.md || fail "security trust model missing threat model doctrine"
grep -Fq "## Degraded-Mode Doctrine" docs/security.md || fail "security trust model missing degraded-mode doctrine"
grep -Fq "## Override Doctrine" docs/security.md || fail "security trust model missing override doctrine"
grep -Fq "malicious model output" docs/security.md || fail "security trust model missing malicious model-output threat"
grep -Fq "quota/fallback weirdness" docs/security.md || fail "security trust model missing quota/fallback threat"
grep -Fq "Codex cannot override" docs/security.md || fail "security trust model missing Codex override boundary"
grep -Fq "What Not To Commit" docs/security.md || fail "security trust model missing commit-exclusion coverage"
grep -Fq "When Not To Run Upkeeper" docs/security.md || fail "security trust model missing when-not-to-run coverage"
grep -Fq "Safe Default Commands" docs/security.md || fail "security trust model missing safe commands coverage"
grep -Fq "tools/upkeeper_precontact_bootstrap.sh" docs/scripts/upkeeper.md || fail "operator guide missing pre-contact bootstrap helper"
grep -Fq "UPKEEPER_LOCAL_ENV_FILE" docs/scripts/upkeeper.md || fail "operator guide missing machine-local env contract"
grep -Fq "tools/upkeeper_precontact_bootstrap.sh" docs/security.md || fail "security trust model missing pre-contact bootstrap helper"
grep -Fq "UPKEEPER_LOCAL_ENV_FILE" docs/security.md || fail "security trust model missing machine-local env contract"
grep -Fq "## Evidence Temperature" docs/preservation-policy.md || fail "preservation policy missing evidence temperature section"
grep -Fq "## Artifact Privacy Classes" docs/preservation-policy.md || fail "preservation policy missing artifact privacy classes"
grep -Fq "## Artifact Handling Matrix" docs/preservation-policy.md || fail "preservation policy missing artifact handling matrix"
grep -Fq "public-safe" docs/preservation-policy.md || fail "preservation policy missing public-safe class"
grep -Fq "private-operator" docs/preservation-policy.md || fail "preservation policy missing private-operator class"
grep -Fq "secret-adjacent" docs/preservation-policy.md || fail "preservation policy missing secret-adjacent class"
grep -Fq "docs/preservation-policy.md" docs/security.md || fail "security docs do not link preservation policy"
grep -Fq "docs/preservation-policy.md" docs/lattice.md || fail "Lattice docs do not link preservation policy"
grep -Fq "docs/preservation-policy.md" docs/compatibility.md || fail "compatibility docs do not link preservation policy"
grep -Fq "## Source Sensitivity Labels" docs/source-rights-metadata.md || fail "source rights metadata missing sensitivity section"
grep -Fq "## Rights And Reuse Fields" docs/source-rights-metadata.md || fail "source rights metadata missing rights fields section"
grep -Fq "## Default Deny Rules" docs/source-rights-metadata.md || fail "source rights metadata missing default deny rules"
grep -Fq "## OSINT And Citation Workflow" docs/source-rights-metadata.md || fail "source rights metadata missing OSINT workflow"
for source_rights_term in \
  public local-private secret-adjacent credential-bearing PII-bearing \
  paid-access license-restricted prompt-safe prompt-unsafe export-safe \
  export-unsafe may_store_metadata may_store_full_text may_quote may_upload \
  may_export may_summarize may_use_for_wikipedia_citation \
  may_include_in_public_evidence_packet may_archive \
  robots_or_terms_restriction; do
  grep -Fq "$source_rights_term" docs/source-rights-metadata.md ||
    fail "source rights metadata missing required term: $source_rights_term"
done
grep -Fq "docs/source-rights-metadata.md" docs/preservation-policy.md || fail "preservation docs do not link source rights metadata"
grep -Fq "docs/source-rights-metadata.md" docs/security.md || fail "security docs do not link source rights metadata"
grep -Fq "docs/source-rights-metadata.md" docs/compatibility.md || fail "compatibility docs do not link source rights metadata"
grep -Fq "Source rights drift" docs/risk-register.md || fail "risk register missing source rights drift risk"
grep -Fq "Upkeeper.conf" README.md || fail "README does not mention the default config file"
grep -Fq "configurations/default.conf" README.md || fail "README does not mention the default configuration profile"
grep -Fq "p26-public-documentation-review.md" README.md || fail "README does not link P26"
grep -Fq "p27-educational-debrief-review.md" README.md || fail "README does not link P27"
grep -Fq "p28-unit-test-harvesting-review.md" README.md || fail "README does not link P28"
grep -Fq "p29-reuse-harvesting-review.md" README.md || fail "README does not link P29"
grep -Fq "p30-stark-protocol-review.md" README.md || fail "README does not link P30"
[[ -s .github/workflows/ci.yml ]] || fail "CI workflow is missing"
grep -Fq ".github/workflows/ci.yml" README.md || fail "README does not mention the CI workflow"
grep -Fq "tools/docs_only_fast_path.sh" .github/workflows/ci.yml || fail "CI workflow does not run shared docs-only fast path"
grep -Fq "scope_args=(--validate)" .github/workflows/ci.yml || fail "CI workflow does not validate docs-only changes through the helper"
grep -Fq "tools/check_public_docs.sh --quick" tools/run_validation_phases.sh || fail "validation phase runner does not run public docs check"
grep -Fq "tools/run_tests.sh" tools/run_validation_phases.sh || fail "validation phase runner does not run unit tests"
grep -Fq "bash -n Upkeeper ChimneySweep FlameOn" tools/run_validation_phases.sh || fail "validation phase runner does not syntax-check launchers"
grep -Fq "age" .github/workflows/ci.yml || fail "CI workflow does not install age for full-burn launcher dependency coverage"
grep -Fq "tools/stress_upkeeper_corpus.sh --local" README.md || fail "README does not document the local stress corpus command"
grep -Fq "tools/docs_only_fast_path.sh --validate" README.md || fail "README does not document the docs-only fast path"
grep -Fq "tools/stress_upkeeper_corpus.sh --local" docs/stress-corpus.md || fail "stress corpus docs do not document the implemented command"
grep -Fq "p26-public-documentation-review.md" prompts/README.md || fail "prompt index does not list P26"
grep -Fq "p27-educational-debrief-review.md" prompts/README.md || fail "prompt index does not list P27"
grep -Fq "p28-unit-test-harvesting-review.md" prompts/README.md || fail "prompt index does not list P28"
grep -Fq "p29-reuse-harvesting-review.md" prompts/README.md || fail "prompt index does not list P29"
grep -Fq "p30-stark-protocol-review.md" prompts/README.md || fail "prompt index does not list P30"

help_text="$(./Upkeeper --help)"
grep -Fq -- "--review-module=p26" <<<"$help_text" || fail "help missing --review-module=p26"
grep -Fq -- "--review-module=p27" <<<"$help_text" || fail "help missing --review-module=p27"
grep -Fq -- "--review-module=p28" <<<"$help_text" || fail "help missing --review-module=p28"
grep -Fq -- "--review-module=p29" <<<"$help_text" || fail "help missing --review-module=p29"
grep -Fq -- "--review-module=p30" <<<"$help_text" || fail "help missing --review-module=p30"
grep -Fq -- "--p26" <<<"$help_text" || fail "help missing --p26"
grep -Fq -- "--p27" <<<"$help_text" || fail "help missing --p27"
grep -Fq -- "--p28" <<<"$help_text" || fail "help missing --p28"
grep -Fq -- "--p29" <<<"$help_text" || fail "help missing --p29"
grep -Fq -- "--p30" <<<"$help_text" || fail "help missing --p30"
grep -Fq -- "--backup-queue" <<<"$help_text" || fail "help missing --backup-queue"
grep -Fq -- "--max-cover" <<<"$help_text" || fail "help missing --max-cover"
grep -Fq -- "--bug-report-only" <<<"$help_text" || fail "help missing --bug-report-only"
grep -Fq -- "--fix-next-issue" <<<"$help_text" || fail "help missing --fix-next-issue"
grep -Fq -- "--issue-workflow-stage=comment|review|apply" <<<"$help_text" || fail "help missing issue workflow stage"
grep -Fq "FlameOn" README.md || fail "README does not document FlameOn"
grep -Fq "ChimneySweep" README.md || fail "README does not document ChimneySweep"
grep -Fq "combined single-issue-fix" README.md || fail "README does not document ChimneySweep combined default"
grep -Fq -- "--cycle-mode=separate" README.md || fail "README does not document ChimneySweep separate cycle mode"
grep -Fq 'comment`, `review`, then `apply`' README.md || fail "README does not document ChimneySweep staged workflow"
grep -Fq "bug-report-only" README.md || fail "README does not document bug-report-only mode"
grep -Fq "fix-next-issue" README.md || fail "README does not document issue-fix mode"
grep -Fq "completions/upkeeper.bash" README.md || fail "README does not document Bash completions"

log "checking for obvious placeholder/legalese public text"
placeholder_pattern='lorem ipsum|apache placeholder|placeholder framework|pending transitional|subsection c-x[0-9]+|rev 14 placeholder|private chat history required'
placeholder_matches="$(git grep -nEI "$placeholder_pattern" -- "${public_text_files[@]}" | grep -v '^tools/check_public_docs[.]sh:.*placeholder_pattern=' || true)"
if [[ -n "$placeholder_matches" ]]; then
  printf '%s\n' "$placeholder_matches" >&2
  fail "public text contains placeholder/legalese wording"
fi

log "checking repo-local Markdown links"
python3 - "$ROOT_DIR" <<'PY'
import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
tracked = set(
    p.strip()
    for p in os.popen("git ls-files --cached --others --exclude-standard '*.md'").read().splitlines()
    if p.strip()
)
link_re = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
errors = []

for rel in sorted(tracked):
    path = root / rel
    text = path.read_text(encoding="utf-8")
    for match in link_re.finditer(text):
        target = match.group(1).strip()
        if not target or target.startswith("#"):
            continue
        if "://" in target or target.startswith("mailto:"):
            continue
        if target.startswith("<") and target.endswith(">"):
            target = target[1:-1]
        target = target.split("#", 1)[0]
        if not target:
            continue
        if target.startswith("/"):
            continue
        if target.startswith("../"):
            candidate = (Path(rel).parent / target).as_posix()
        else:
            candidate = (Path(rel).parent / target).as_posix()
        normalized = os.path.normpath(candidate)
        if normalized.startswith("../"):
            continue
        if normalized not in tracked and not (root / normalized).exists():
            errors.append(f"{rel}: broken link target {match.group(1)}")

if errors:
    for error in errors:
        print(error, file=sys.stderr)
    sys.exit(1)
PY

git diff --check -- .github README.md AGENTS.md PLANS.md Upkeeper.conf change_notes_*.md configurations docs lib/upkeeper/README.md prompts templates tools

log "public documentation checks passed"
