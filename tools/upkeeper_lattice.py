#!/usr/bin/env python3
"""Upkeeper Lattice: local SQLite evidence ledger and query surface."""

from __future__ import annotations

import argparse
import contextlib
import errno
import fnmatch
import hashlib
import hmac
import io
import json
import os
import re
import shlex
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 1
SCHEMA_ROW_VERSION = 1
TEXT_SAMPLE_SIZE = 4096
CANDIDATE_STATE_PRIORITY = {"selected": 3, "eligible": 2, "excluded": 1}

EXIT_SUCCESS = 0
EXIT_NO_MATCH = 1
EXIT_USAGE = 2
EXIT_DB_UNAVAILABLE = 3
EXIT_UNSAFE_DB_PATH = 4
EXIT_SCHEMA_MISMATCH = 5
EXIT_INTEGRITY = 6
EXIT_GIT_UNAVAILABLE = 7
EXIT_IMPORT_CONFLICT = 8
EXIT_RECOVERY_INCOMPLETE = 9

SOURCE_KINDS = {
    "local_git",
    "github_api",
    "upkeeper_log",
    "transcript",
    "tool_failure_marker",
    "change_notes",
    "lattice_import",
    "lattice_export",
    "recovery",
    "operator",
    "wrapper_observed",
    "compiled_prompt",
    "artifact",
}

COMPLETED_OUTCOMES = {"clean", "fixed", "regression_found"}
PASS_OUTCOMES_REQUIRING_APPLICABLE_TRUE = {"clean", "fixed", "regression_found", "blocked"}
ALLOWED_OUTCOMES = {
    "planned",
    "not_applicable",
    "clean",
    "fixed",
    "blocked",
    "regression_found",
    "unknown",
}
REVIEW_OUTCOME_MARKERS = (
    "REVIEWED_AND_FIXED",
    "REVIEWED_AND_REPORTED",
    "REVIEWED_CLEAN",
    "STOPPED_ON_BLOCKER",
)
REVIEW_OUTCOME_LINE_PATTERN = re.compile(
    r"^(?:UPKEEPER_REVIEW_OUTCOME\s*=\s*)?("
    + "|".join(REVIEW_OUTCOME_MARKERS)
    + r")(?:\s+for\s+.+)?$"
)
UPKEEPER_STATUS_MARKERS = ("WORK_DONE", "NO_CHANGES", "NO_BACKEND_TASK", "BLOCKED")
UPKEEPER_STATUS_CONTRACT_LINE = re.compile(rf"^UPKEEPER_STATUS:\s*({'|'.join(UPKEEPER_STATUS_MARKERS)})\s*$")
UPKEEPER_STATUS_ALIAS = {"NO_CHANGES": "WORK_DONE"}

SCRIPT_EXTS = {
    ".awk",
    ".bash",
    ".cjs",
    ".fish",
    ".go",
    ".js",
    ".jsx",
    ".ksh",
    ".lua",
    ".mjs",
    ".pl",
    ".ps1",
    ".psm1",
    ".py",
    ".rb",
    ".rs",
    ".sh",
    ".ts",
    ".tsx",
    ".zsh",
}
BUILD_NAMES = {
    "Dockerfile",
    "Justfile",
    "Makefile",
    "Rakefile",
    "dockerfile",
    "justfile",
    "makefile",
}
TEST_DIRS = {"__tests__", "test", "tests"}
REDACTED_PATH_PREFIX = "path-sha256:"
PASS_RESULT_PATH_HMAC_PREFIX = "path-hmac-sha256:"
METADATA_HMAC_PREFIX = "meta-hmac-sha256:"
CONTENT_HMAC_PREFIX = "content-hmac-sha256:"
CONTRIBUTOR_HASH_PREFIX = "contributor-sha256:"
COMMIT_SUBJECT_HASH_PREFIX = "subject-sha256:"
BRANCH_HMAC_PREFIX = "branch-hmac-sha256:"
REMOTE_HMAC_PREFIX = "remote-hmac-sha256:"
SSH_REMOTE_HMAC_PREFIX = "ssh-remote-hmac-sha256:"
LOCAL_REMOTE_HMAC_PREFIX = "local-remote-hmac-sha256:"
WORKTREE_SNAPSHOT_UNTRACKED_MODES = ("no", "normal", "all")
WORKTREE_SNAPSHOT_UNTRACKED_FILES_ENV = "UPKEEPER_LATTICE_WORKTREE_UNTRACKED_FILES"
TOOL_FAILURE_MARKER_ID_HEX_LENGTH = 24
UPKEEPER_VERBOSE_METADATA_ENV = "UPKEEPER_VERBOSE_METADATA"
UPKEEPER_RAW_REPO_IDENTITY_ENV = "UPKEEPER_LATTICE_RAW_REPO_IDENTITY"
SENSITIVE_WORKTREE_PATH_SUFFIXES = {".pem", ".p12", ".pfx", ".key", ".der", ".cer", ".crt", ".asc", ".gpg", ".jks", ".keystore"}
SENSITIVE_WORKTREE_PATH_PARTS = {
    ".env",
    ".env.local",
    ".env.production",
    ".npmrc",
    ".pypirc",
    ".netrc",
    "id_rsa",
    "id_dsa",
    "id_ecdsa",
    "id_ed25519",
    ".kube",
    "kubeconfig",
}
SENSITIVE_WORKTREE_PATH_FRAGMENTS = {
    "secret",
    "secrets",
    "credential",
    "credentials",
    "password",
    "private_key",
    "token",
}
WORKTREE_PATH_CLASS_TRACKED = "tracked"
WORKTREE_PATH_CLASS_UNTRACKED = "untracked"
WORKTREE_PATH_CLASS_RENAMED_NEW = "renamed_new"
WORKTREE_PATH_CLASS_RENAMED_OLD = "renamed_old"
WORKTREE_PATH_CLASS_SENSITIVE = "sensitive"
SOURCE_RECORD_PATH_HMAC_KINDS = {
    "lattice_export",
    "lattice_import",
    "recovery",
    "tool_failure_marker",
    "upkeeper_log",
}
TRANSIENT_ARTIFACT_KINDS = {"transcript", "compiled_prompt", "last_message"}
OUT_OF_SCOPE_TRANSIENT_ARTIFACT_KINDS = {"compiled_prompt", "last_message"}
WORKTREE_RUNTIME_MESSAGE_ARTIFACT_PATH_PREFIXES = (
    "runtime/upkeeper-transcripts/",
    "runtime/last-message",
)
ARTIFACT_RETENTION_CLASSES = {
    "transcript": "transient",
    "compiled_prompt": "transient",
    "last_message": "transient",
    "upkeeper_log": "operator_local",
    "postmortem_report": "operator_local",
    "startup_anomaly_state": "operator_local",
    "wrapper_health_state": "operator_local",
    "quota_block_marker": "operator_local",
    "backup": "durable",
}
ARTIFACT_SCOPE_PATHS = {
    "transcript": "runtime",
    "compiled_prompt": "runtime",
    "last_message": "runtime",
    "upkeeper_log": "repo",
    "startup_anomaly_state": "runtime",
    "postmortem_report": "runtime",
    "wrapper_health_state": "runtime",
    "quota_block_marker": "runtime",
    "backup": "runtime",
}


def normalize_hex_sha256(raw: Any) -> str | None:
    text = str(raw).strip().lower() if has_meaningful_value(raw) else ""
    if len(text) != 64:
        return None
    if any(ch not in "0123456789abcdef" for ch in text):
        return None
    return text


def is_upkeeper_temp_artifact_path(path: Path) -> bool:
    candidate = path.resolve(strict=False)
    temp_root = Path(tempfile.gettempdir()).resolve()
    if not path_under(candidate, temp_root):
        return False
    try:
        relative = candidate.relative_to(temp_root)
    except ValueError:
        return False
    return bool(relative.parts) and relative.parts[0].startswith("upkeeper-")


def canonical_artifact_path(root: Path, path: str, artifact_kind: str) -> Path:
    candidate = Path(path).expanduser()
    path_abs = candidate.absolute() if candidate.is_absolute() else (Path.cwd() / candidate).absolute()
    normalized = Path(os.path.normpath(str(path_abs)))
    scope = ARTIFACT_SCOPE_PATHS.get(artifact_kind, "runtime")
    runtime_root = (root / "runtime").resolve()
    scope_root = root.resolve() if scope == "repo" else runtime_root
    if has_forbidden_symlink(path_abs, scope_root):
        fail(f"artifact path contains forbidden symlink for {artifact_kind}: {normalized}", EXIT_USAGE)
    if not path_under(normalized, scope_root):
        if artifact_kind in OUT_OF_SCOPE_TRANSIENT_ARTIFACT_KINDS and is_upkeeper_temp_artifact_path(normalized):
            temp_root = Path(tempfile.gettempdir()).resolve()
            if has_forbidden_symlink(normalized, temp_root):
                fail(f"artifact path contains forbidden symlink for {artifact_kind}: {normalized}", EXIT_USAGE)
            return normalized
        fail(
            f"unsafe artifact path for {artifact_kind}: {normalized} is outside {scope_root}",
            EXIT_USAGE,
        )
    if has_forbidden_symlink(normalized, scope_root):
        fail(f"artifact path contains forbidden symlink for {artifact_kind}: {normalized}", EXIT_USAGE)
    return normalized
REDACTABLE_PATH_KEYS = {
    "path",
    "paths",
    "old_path",
    "canonical_path",
    "current_path",
    "first_seen_root_path",
    "current_root_path",
    "working_tree_path",
    "source_path",
    "target_path",
    "selected_path",
    "recovery_path",
    "input_path",
    "output_path",
    "detail_path",
    "remote_url",
    "alias_value",
    "source_uri",
    "repo_alias_id",
}
REDACTION_KEY_NORMALIZER = re.compile(r"(?<!^)(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])")
REDACTION_KEY_SEPARATORS = re.compile(r"[\.\-\s]+")
REDACTION_KEY_UNDERSCORE_COLLAPSE = re.compile(r"_+")
STRUCTURED_REDACTION_STRING_KEYS = {"raw_text", "details_json", "parsed_json"}
CONTRIBUTOR_REDACT_KEYS = {"name", "email", "github_login"}
INLINE_ASSIGNMENT_PATTERN = re.compile(
    r"(?P<prefix>(?:^|\s))(?P<key>[A-Za-z0-9_.-]+)=(?P<quote>['\"]?)(?P<value>.*?)(?P=quote)(?=(?:\s+[A-Za-z0-9_.-]+=)|$)"
)
UPKEEPER_LOG_SOURCE_SAFE_KEYS = {
    "timestamp",
    "level",
    "event",
    "cycle",
    "run_hash",
    "execution_origin",
    "dirty_paths",
    "dry_run",
    "status_marker",
    "codex_exit",
    "exit_code",
    "codex_exec_started",
}
UPKEEPER_LOG_CYCLE_START_SAFE_KEYS = {"execution_origin", "dirty_paths", "dry_run"}
UPKEEPER_LOG_REVIEW_PRESELECT_SAFE_KEYS = {"basis"}
UPKEEPER_LOG_SUMMARY_SAFE_KEYS = {"status_marker", "codex_exit"}
UPKEEPER_LOG_EXIT_SAFE_KEYS = {"exit_code", "codex_exec_started"}
CYCLE_START_SAFE_KEYS = {
    "timestamp",
    "level",
    "event",
    "cycle",
    "cycle_id",
    "run_hash",
    "execution_origin",
    "dirty_paths",
    "dirty_path_count",
    "dry_run",
    "start_epoch",
}
CYCLE_START_PATH_KEYS = {
    "script",
    "script_path",
    "implementation",
    "implementation_path",
    "cwd",
    "config",
    "config_file",
    "manifest",
    "manifest_path",
    "target_file",
    "target_root",
    "codex_home",
}
CYCLE_START_HASH_KEY_FRAGMENTS = (
    "path",
    "cwd",
    "root",
    "glob",
    "label",
    "review_module",
    "review_modules",
    "manifest",
    "fallback",
    "parent",
    "child",
    "pid",
    "process",
    "boot",
    "uptime",
    "target",
)
PASS_RESULT_ALLOWED_KEYS = {
    "pass",
    "file",
    "applicable",
    "outcome",
    "changed",
    "regression",
}
RAW_STORAGE_MODES = {"none", "minimal", "limited", "full"}
RAW_STORAGE_COMPAT_MODES = RAW_STORAGE_MODES | {"debug"}
PASS_RESULT_DEBUG_STORAGE_VALUES = {"debug", "full"}
DEFAULT_RAW_STORAGE_MODE = "limited"
MINIMAL_PARSED_SOURCE_RECORDS = {
    ("lattice_export", ""),
    ("recovery", "recover"),
    ("recovery", "recover_artifacts"),
}
LIMITED_PARSED_SOURCE_RECORDS = MINIMAL_PARSED_SOURCE_RECORDS | {
    ("local_git", ""),
    ("transcript", "rejected"),
    ("upkeeper_log", ""),
}


REQUIRED_TABLES = [
    "schema_meta",
    "schema_migrations",
    "repositories",
    "repo_aliases",
    "source_records",
    "files",
    "file_paths",
    "file_snapshots",
    "worktree_snapshots",
    "worktree_snapshot_paths",
    "cycles",
    "cycle_links",
    "selection_runs",
    "selection_candidates",
    "review_passes",
    "file_pass_runs",
    "pass_run_attributes",
    "file_events",
    "artifact_refs",
    "contributors",
    "git_commits",
    "git_file_changes",
    "tool_failures",
    "tool_failure_samples",
    "regression_events",
    "regression_causes",
    "regression_corrections",
    "change_log_entries",
    "change_log_file_refs",
    "lattice_imports",
    "lattice_import_conflicts",
    "lattice_exports",
    "import_cursors",
    "extension_namespaces",
    "extension_fact_types",
    "extension_facts",
    "operator_annotations",
    "file_pass_rollups",
    "file_fragility_rollups",
    "file_git_churn_rollups",
    "file_selection_rollups",
    "file_failure_rollups",
]

REQUIRED_INDEXES = {
    "idx_artifact_refs_unique_identity_digest": "artifact_refs",
    "idx_artifact_refs_unique_identity_missing_digest": "artifact_refs",
    "idx_artifact_refs_unique_identity_coalesced": "artifact_refs",
    "idx_cycles_repo_cycle": "cycles",
    "idx_cycles_repo_selected_path": "cycles",
    "idx_files_repo_current_path": "files",
    "idx_file_paths_file_path": "file_paths",
    "idx_selection_candidates_run_path": "selection_candidates",
    "idx_selection_candidates_run_state_rank": "selection_candidates",
    "idx_file_pass_runs_repo_file_pass": "file_pass_runs",
    "idx_file_pass_runs_repo_pass_outcome": "file_pass_runs",
    "idx_file_events_repo_file_epoch": "file_events",
    "idx_git_commits_repo_sha": "git_commits",
    "idx_git_file_changes_unique_event": "git_file_changes",
    "idx_git_file_changes_repo_path_epoch": "git_file_changes",
    "idx_regression_events_repo_file_epoch": "regression_events",
    "idx_extension_facts_lookup": "extension_facts",
    "idx_pass_run_attributes_lookup": "pass_run_attributes",
}


PASS_REGISTRY: list[dict[str, Any]] = [
    {
        "pass_code": f"P{i}",
        "title": title,
        "prompt_source_path": "prompts/default-review.md",
        "default_in_repertoire": True,
        "module_prompt": False,
        "aliases": [],
        "active": True,
        "introduced_version": "v1.0.0",
        "applicability_hint": hint,
        "schedule_hint": schedule,
    }
    for i, title, hint, schedule in [
        (1, "Comprehensive Code Review", "broad source review", "default repertoire"),
        (2, "Branch and PR Housekeeping", "repo-level operations", "slow cadence"),
        (3, "Targeted Single-Script Deep Dive", "scripts/tools", "timestamp selected"),
        (4, "Correctness Review", "scripts/tools", "default repertoire"),
        (5, "Robustness Review", "scripts/tools", "default repertoire"),
        (6, "Portability Review", "scripts/tools", "default repertoire"),
        (7, "Shell Safety Review", "scripts/tools", "default repertoire"),
        (8, "Test Suite Review", "tests", "test files"),
        (9, "Error Handling Review", "scripts/tools", "default repertoire"),
        (10, "Input Validation Review", "scripts/tools", "default repertoire"),
        (11, "Output Contract Review", "scripts/tools", "default repertoire"),
        (12, "Local Duplication Review", "scripts/tools", "default repertoire"),
        (13, "Dependency Use Review", "scripts/tools", "default repertoire"),
        (14, "Observability Review", "scripts/tools", "default repertoire"),
        (15, "Operator Ergonomics Review", "scripts/tools", "default repertoire"),
        (16, "Manifest and Dependency File Review", "manifests/dependency files", "manifest files"),
        (17, "Idempotence Review", "scripts/tools", "default repertoire"),
        (18, "State and Cleanup Review", "scripts/tools", "default repertoire"),
        (19, "Security Boundary Review", "scripts/tools", "default repertoire"),
        (20, "Failure Mode Review", "scripts/tools", "default repertoire"),
        (21, "Documentation Fit Review", "scripts/tools", "default repertoire"),
        (22, "Selected File Persistence Review", "all file types", "always"),
        (23, "Data Contract Negative Fixture Audit", "data/input-boundary files", "applicability gated"),
    ]
]
PASS_REGISTRY.extend(
    [
        {
            "pass_code": "P24",
            "title": "De-LLM-ing Viability Review",
            "prompt_source_path": "prompts/p24-de-llm-ing-viability-review.md",
            "default_in_repertoire": False,
            "module_prompt": True,
            "aliases": ["de-llm", "de-llm-ing", "dellm", "de-llming"],
            "active": True,
            "introduced_version": "v1.1.8",
            "applicability_hint": "LLM/Codex-adjacent behavior",
            "schedule_hint": "explicit review module",
        },
        {
            "pass_code": "P25",
            "title": "Contract And Intent Compliance Review",
            "prompt_source_path": "prompts/p25-contract-intent-compliance-review.md",
            "default_in_repertoire": False,
            "module_prompt": True,
            "aliases": ["contract", "contract-intent", "intent", "architecture"],
            "active": True,
            "introduced_version": "v1.1.8",
            "applicability_hint": "contract and architecture surfaces",
            "schedule_hint": "explicit review module",
        },
        {
            "pass_code": "P26",
            "title": "Public Documentation And Readability Review",
            "prompt_source_path": "prompts/p26-public-documentation-review.md",
            "default_in_repertoire": False,
            "module_prompt": True,
            "aliases": ["docs", "documentation", "public-docs", "readability"],
            "active": True,
            "introduced_version": "v1.1.9",
            "applicability_hint": "public docs, comments, prompts, help, release notes",
            "schedule_hint": "explicit review module",
        },
        {
            "pass_code": "P27",
            "title": "Educational Debrief Review",
            "prompt_source_path": "prompts/p27-educational-debrief-review.md",
            "default_in_repertoire": False,
            "module_prompt": True,
            "aliases": ["education", "debrief", "learning"],
            "active": True,
            "introduced_version": "v1.1.9",
            "applicability_hint": "saved educational debrief after useful work",
            "schedule_hint": "explicit review module",
        },
        {
            "pass_code": "P28",
            "title": "Unit Test Harvesting Review",
            "prompt_source_path": "prompts/p28-unit-test-harvesting-review.md",
            "default_in_repertoire": False,
            "module_prompt": True,
            "aliases": ["unit-test", "test-harvest", "fixture-harvest"],
            "active": True,
            "introduced_version": "v1.1.11",
            "applicability_hint": "cheap deterministic tests and fixtures",
            "schedule_hint": "explicit review module",
        },
        {
            "pass_code": "P29",
            "title": "Reuse Harvesting Review",
            "prompt_source_path": "prompts/p29-reuse-harvesting-review.md",
            "default_in_repertoire": False,
            "module_prompt": True,
            "aliases": ["reuse", "reuse-harvest", "library-reuse", "function-reuse", "asset-reuse"],
            "active": True,
            "introduced_version": "v1.1.19",
            "applicability_hint": "stable reusable assets and helper extraction",
            "schedule_hint": "explicit review module",
        },
        {
            "pass_code": "P30",
            "title": "Stark Protocol Review",
            "prompt_source_path": "prompts/p30-stark-protocol-review.md",
            "default_in_repertoire": False,
            "module_prompt": True,
            "aliases": [
                "stark",
                "stark-protocol",
                "permanent-hardening",
                "hardening",
                "non-regression",
                "regression-proof",
                "no-repeat",
                "final-hardening",
            ],
            "active": True,
            "introduced_version": "v1.2.18",
            "applicability_hint": "permanent hardening and non-regression barriers",
            "schedule_hint": "explicit review module",
        },
    ]
)


CREATE_TABLE_SQL = [
    """
    CREATE TABLE IF NOT EXISTS schema_meta (
      key text primary key,
      value text not null
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS schema_migrations (
      migration_id integer primary key,
      from_version integer,
      to_version integer,
      applied_epoch integer not null,
      status text,
      script_hash text,
      backup_path text,
      details_json text
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS repositories (
      repo_id integer primary key,
      repo_key text,
      root_path text not null,
      first_seen_root_path text,
      current_root_path text,
      working_tree_path text,
      git_common_dir text,
      head_sha text,
      head_tree_sha text,
      branch_name text,
      remote_url text,
      origin_url_hash text,
      created_epoch integer not null,
      last_seen_epoch integer not null
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS repo_aliases (
      repo_alias_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      alias_kind text not null,
      alias_value text not null,
      first_seen_epoch integer,
      last_seen_epoch integer,
      unique(alias_kind, alias_value)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS source_records (
      source_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      source_kind text not null,
      source_path text,
      source_uri text,
      source_epoch integer,
      imported_epoch integer not null,
      source_line integer,
      raw_ref text,
      raw_text text,
      raw_sha256 text,
      parsed_json text,
      parse_status text,
      fact_confidence text
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS files (
      file_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      canonical_path text not null,
      first_seen_epoch integer,
      last_seen_epoch integer,
      current_path text not null,
      current_state text not null default 'active',
      unique(repo_id, canonical_path)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS file_paths (
      file_path_id integer primary key,
      file_id integer not null references files(file_id),
      path text not null,
      first_seen_epoch integer,
      last_seen_epoch integer,
      source_id integer references source_records(source_id),
      unique(file_id, path)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS file_snapshots (
      snapshot_id integer primary key,
      file_id integer references files(file_id),
      repo_id integer not null references repositories(repo_id),
      path text not null,
      observed_epoch integer not null,
      source_id integer references source_records(source_id),
      git_status text,
      content_state text,
      head_blob text,
      worktree_hash text,
      mtime_epoch integer,
      mtime_ns integer,
      size_bytes integer,
      executable integer,
      ignored integer,
      generated integer,
      test_path integer
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS worktree_snapshots (
      worktree_snapshot_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      cycle_pk integer references cycles(cycle_pk),
      snapshot_kind text not null,
      observed_epoch integer not null,
      git_head_sha text,
      branch_name text,
      dirty_path_count integer,
      tracked_modified_path_count integer,
      untracked_path_count integer,
      source_id integer references source_records(source_id),
      details_json text
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS worktree_snapshot_paths (
      worktree_snapshot_path_id integer primary key,
      worktree_snapshot_id integer not null references worktree_snapshots(worktree_snapshot_id),
      file_id integer references files(file_id),
      path text not null,
      path_hmac text,
      path_class text,
      status text,
      old_path text,
      old_path_hmac text,
      old_path_class text,
      head_blob text,
      worktree_hash text,
      size_bytes integer,
      mtime_epoch integer,
      mtime_ns integer
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS cycles (
      cycle_pk integer primary key,
      repo_id integer not null references repositories(repo_id),
      cycle_id text not null,
      run_hash text not null,
      execution_origin text,
      model text,
      effort text,
      mode text,
      config_file text,
      branch_name text,
      head_sha text,
      head_tree_sha text,
      upstream_ref text,
      worktree_dirty integer,
      start_epoch integer,
      end_epoch integer,
      status_marker text,
      review_outcome text,
      codex_exit integer,
      wrapper_exit integer,
      finish_reason text,
      finish_level text,
      codex_exec_started integer,
      dry_run integer,
      selected_file_id integer references files(file_id),
      selected_path text,
      selection_basis text,
      source_id integer references source_records(source_id),
      unique(repo_id, cycle_id, run_hash)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS cycle_links (
      cycle_link_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      parent_cycle_pk integer references cycles(cycle_pk),
      child_cycle_pk integer references cycles(cycle_pk),
      link_kind text not null,
      trigger text,
      parent_cycle_id_text text,
      child_cycle_id_text text,
      source_id integer references source_records(source_id),
      created_epoch integer not null
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS selection_runs (
      selection_run_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      cycle_pk integer references cycles(cycle_pk),
      selector_version text not null,
      source_safe_boundary_version text not null,
      mode_requested text not null,
      mode_effective text not null,
      priority_gate text not null,
      generated_epoch integer not null,
      git_head_sha text,
      dirty_path_count integer,
      eligible_count integer,
      excluded_count integer,
      incomplete integer not null default 0,
      incomplete_reason text,
      selected_file_id integer references files(file_id),
      selected_path text,
      selected_rank integer,
      details_json text
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS selection_candidates (
      selection_candidate_id integer primary key,
      selection_run_id integer not null references selection_runs(selection_run_id),
      file_id integer references files(file_id),
      path text not null,
      candidate_state text not null,
      rank integer,
      mtime_epoch integer,
      git_status text,
      content_state text,
      head_blob text,
      worktree_hash text,
      exclusion_reason text,
      score_json text,
      source_id integer references source_records(source_id),
      unique(selection_run_id, path)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS review_passes (
      pass_id integer primary key,
      pass_code text not null,
      title text,
      prompt_source_path text,
      introduced_version text,
      active integer not null default 1,
      unique(pass_code)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS file_pass_runs (
      file_pass_run_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      file_id integer references files(file_id),
      cycle_pk integer references cycles(cycle_pk),
      pass_id integer not null references review_passes(pass_id),
      pass_code text not null,
      planned integer not null default 0,
      applicable integer,
      attempted integer,
      outcome text,
      changed integer,
      regression integer,
      confidence text,
      authority_rank integer,
      source_id integer references source_records(source_id),
      raw_line text,
      created_epoch integer not null
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS pass_run_attributes (
      attribute_id integer primary key,
      file_pass_run_id integer not null references file_pass_runs(file_pass_run_id),
      namespace text not null,
      key text not null,
      value_type text not null,
      value_text text,
      value_integer integer,
      value_real real,
      value_json text,
      unit text,
      confidence text,
      source_id integer references source_records(source_id),
      created_epoch integer not null,
      unique(file_pass_run_id, namespace, key, source_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS file_events (
      event_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      file_id integer references files(file_id),
      cycle_pk integer references cycles(cycle_pk),
      source_id integer references source_records(source_id),
      event_kind text not null,
      event_epoch integer not null,
      path text,
      confidence text,
      details_json text
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS artifact_refs (
      artifact_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      cycle_pk integer references cycles(cycle_pk),
      source_id integer references source_records(source_id),
      artifact_kind text not null,
      path text,
      exists_at_record_time integer,
      size_bytes integer,
      sha256 text,
      created_epoch integer,
      observed_epoch integer not null,
      retained integer,
      details_json text
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS contributors (
      contributor_id integer primary key,
      name text,
      email text,
      github_login text,
      identity_hash text,
      pii_included integer not null default 0,
      unique(name, email)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS git_commits (
      commit_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      sha text not null,
      author_id integer references contributors(contributor_id),
      committer_id integer references contributors(contributor_id),
      author_epoch integer,
      committer_epoch integer,
      subject text,
      subject_hash text,
      subject_length integer,
      subject_included integer not null default 0,
      source_id integer references source_records(source_id),
      unique(repo_id, sha)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS git_file_changes (
      git_file_change_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      commit_id integer not null references git_commits(commit_id),
      file_id integer references files(file_id),
      status text,
      path text not null,
      old_path text,
      additions integer,
      deletions integer,
      change_epoch integer,
      source_id integer references source_records(source_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS tool_failures (
      tool_failure_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      file_id integer references files(file_id),
      marker_id text,
      status text,
      first_seen_epoch integer,
      last_seen_epoch integer,
      resolved_epoch integer,
      first_failure_kind text,
      last_failure_kind text,
      failure_count integer,
      source_id integer references source_records(source_id),
      raw_json text
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS tool_failure_samples (
      tool_failure_sample_id integer primary key,
      tool_failure_id integer references tool_failures(tool_failure_id),
      repo_id integer not null references repositories(repo_id),
      cycle_pk integer references cycles(cycle_pk),
      command_kind text,
      command_text text,
      command_signature text,
      exit_line text,
      observed_epoch integer,
      source_id integer references source_records(source_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS regression_events (
      regression_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      file_id integer references files(file_id),
      cycle_pk integer references cycles(cycle_pk),
      marked_epoch integer not null,
      confidence text not null,
      detector text,
      reason text,
      status text not null default 'active',
      source_id integer references source_records(source_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS regression_causes (
      regression_cause_id integer primary key,
      regression_id integer not null references regression_events(regression_id),
      suspected_cause_cycle_pk integer references cycles(cycle_pk),
      suspected_cause_commit_id integer references git_commits(commit_id),
      cause_file_id integer references files(file_id),
      confidence text not null,
      reason text
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS regression_corrections (
      correction_id integer primary key,
      regression_id integer not null references regression_events(regression_id),
      repo_id integer not null references repositories(repo_id),
      corrected_epoch integer not null,
      correction_kind text not null,
      old_confidence text,
      new_confidence text,
      reason text,
      source_id integer references source_records(source_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS change_log_entries (
      change_log_entry_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      version text,
      entry_date text,
      item_number integer,
      source_path text,
      source_line integer,
      text text not null,
      source_id integer references source_records(source_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS change_log_file_refs (
      change_log_file_ref_id integer primary key,
      change_log_entry_id integer not null references change_log_entries(change_log_entry_id),
      file_id integer references files(file_id),
      path text not null,
      confidence text not null,
      source_id integer references source_records(source_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS lattice_imports (
      import_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      import_kind text not null,
      started_epoch integer not null,
      finished_epoch integer,
      status text,
      rows_seen integer,
      rows_written integer,
      conflicts integer,
      details_json text
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS lattice_import_conflicts (
      conflict_id integer primary key,
      import_id integer references lattice_imports(import_id),
      repo_id integer not null references repositories(repo_id),
      row_type text not null,
      logical_key text not null,
      existing_hash text,
      incoming_hash text,
      resolution text not null default 'kept_existing',
      details_json text
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS lattice_exports (
      export_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      export_kind text not null,
      output_path text not null,
      started_epoch integer not null,
      finished_epoch integer,
      row_count integer,
      sha256 text
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS import_cursors (
      import_cursor_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      import_kind text not null,
      scope text not null,
      cursor_value text,
      cursor_epoch integer,
      history_complete integer,
      incomplete_reason text,
      source_id integer references source_records(source_id),
      unique(repo_id, import_kind, scope)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS extension_namespaces (
      namespace text primary key,
      owner text,
      description text,
      introduced_epoch integer not null,
      active integer not null default 1,
      source_id integer references source_records(source_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS extension_fact_types (
      fact_type_id integer primary key,
      namespace text not null references extension_namespaces(namespace),
      key text not null,
      subject_type text not null,
      value_type text not null,
      allowed_values_json text,
      description text,
      schema_version integer not null default 1,
      active integer not null default 1,
      unique(namespace, key, subject_type)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS extension_facts (
      extension_fact_id integer primary key,
      namespace text not null references extension_namespaces(namespace),
      key text not null,
      subject_type text not null,
      subject_pk integer,
      repo_id integer references repositories(repo_id),
      file_id integer references files(file_id),
      cycle_pk integer references cycles(cycle_pk),
      file_pass_run_id integer references file_pass_runs(file_pass_run_id),
      value_type text not null,
      value_text text,
      value_integer integer,
      value_real real,
      value_json text,
      unit text,
      confidence text,
      source_id integer references source_records(source_id),
      created_epoch integer not null,
      unique(namespace, key, subject_type, subject_pk, source_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS operator_annotations (
      annotation_id integer primary key,
      repo_id integer not null references repositories(repo_id),
      file_id integer references files(file_id),
      cycle_pk integer references cycles(cycle_pk),
      annotation_kind text not null,
      target_table text,
      target_pk integer,
      text text not null,
      created_epoch integer not null,
      source_id integer references source_records(source_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS file_pass_rollups (
      file_id integer primary key references files(file_id),
      planned_count integer not null default 0,
      applicable_count integer not null default 0,
      attempted_count integer not null default 0,
      completed_count integer not null default 0,
      blocked_count integer not null default 0,
      changed_count integer not null default 0,
      clean_count integer not null default 0,
      not_applicable_count integer not null default 0,
      unknown_count integer not null default 0,
      regression_count integer not null default 0,
      updated_epoch integer not null
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS file_fragility_rollups (
      file_id integer primary key references files(file_id),
      score_version integer not null,
      score real not null,
      details_json text,
      updated_epoch integer not null
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS file_git_churn_rollups (
      file_id integer primary key references files(file_id),
      git_churn_count integer not null default 0,
      latest_change_epoch integer,
      updated_epoch integer not null
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS file_selection_rollups (
      file_id integer primary key references files(file_id),
      selected_count integer not null default 0,
      last_selected_epoch integer,
      updated_epoch integer not null
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS file_failure_rollups (
      file_id integer primary key references files(file_id),
      open_tool_failures integer not null default 0,
      updated_epoch integer not null
    )
    """,
]

CREATE_INDEX_SQL = [
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_artifact_refs_unique_identity_digest ON artifact_refs(repo_id, artifact_kind, path, sha256) WHERE sha256 IS NOT NULL",
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_artifact_refs_unique_identity_missing_digest ON artifact_refs(repo_id, artifact_kind, path) WHERE sha256 IS NULL",
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_artifact_refs_unique_identity_coalesced ON artifact_refs(repo_id, artifact_kind, path, coalesce(sha256, ''))",
    "CREATE INDEX IF NOT EXISTS idx_cycles_repo_cycle ON cycles(repo_id, cycle_id)",
    "CREATE INDEX IF NOT EXISTS idx_cycles_repo_selected_path ON cycles(repo_id, selected_path)",
    "CREATE INDEX IF NOT EXISTS idx_files_repo_current_path ON files(repo_id, current_path)",
    "CREATE INDEX IF NOT EXISTS idx_file_paths_file_path ON file_paths(file_id, path)",
    "CREATE INDEX IF NOT EXISTS idx_selection_candidates_run_path ON selection_candidates(selection_run_id, path)",
    "CREATE INDEX IF NOT EXISTS idx_selection_candidates_run_state_rank ON selection_candidates(selection_run_id, candidate_state, rank)",
    "CREATE INDEX IF NOT EXISTS idx_file_pass_runs_repo_file_pass ON file_pass_runs(repo_id, file_id, pass_code)",
    "CREATE INDEX IF NOT EXISTS idx_file_pass_runs_repo_pass_outcome ON file_pass_runs(repo_id, pass_code, outcome)",
    "CREATE INDEX IF NOT EXISTS idx_file_events_repo_file_epoch ON file_events(repo_id, file_id, event_epoch)",
    "CREATE INDEX IF NOT EXISTS idx_git_commits_repo_sha ON git_commits(repo_id, sha)",
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_contributors_identity_hash ON contributors(identity_hash) WHERE identity_hash IS NOT NULL",
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_git_file_changes_unique_event ON git_file_changes(repo_id, commit_id, path, coalesce(old_path, ''), coalesce(status, ''))",
    "CREATE INDEX IF NOT EXISTS idx_git_file_changes_repo_path_epoch ON git_file_changes(repo_id, path, change_epoch)",
    "CREATE INDEX IF NOT EXISTS idx_regression_events_repo_file_epoch ON regression_events(repo_id, file_id, marked_epoch)",
    "CREATE INDEX IF NOT EXISTS idx_extension_facts_lookup ON extension_facts(namespace, key, subject_type, subject_pk)",
    "CREATE INDEX IF NOT EXISTS idx_pass_run_attributes_lookup ON pass_run_attributes(file_pass_run_id, namespace, key)",
    "CREATE INDEX IF NOT EXISTS idx_source_records_identity ON source_records(repo_id, source_kind, coalesce(source_path, ''), coalesce(source_line, -1), coalesce(raw_sha256, ''))",
]


def epoch_now() -> int:
    return int(time.time())


def safe_output_text(raw: str) -> str:
    return raw.encode("utf-8", "surrogateescape").decode("utf-8", "backslashreplace")


def has_surrogate_codepoint(raw: str) -> bool:
    return any(0xD800 <= ord(ch) <= 0xDFFF for ch in raw)


def encode_path_text(raw: str) -> str:
    pieces: list[str] = []
    for ch in raw:
        codepoint = ord(ch)
        if ch == "\\":
            pieces.append("\\\\")
        elif 0xDC80 <= codepoint <= 0xDCFF:
            pieces.append(f"\\x{codepoint - 0xDC00:02x}")
        elif codepoint < 0x20 or codepoint == 0x7F:
            pieces.append(f"\\x{codepoint:02x}")
        else:
            pieces.append(ch)
    return "".join(pieces)


def decode_path_text(raw: str) -> str:
    decoded = bytearray()
    i = 0
    while i < len(raw):
        ch = raw[i]
        if ch != "\\":
            decoded.extend(ch.encode("utf-8", "surrogateescape"))
            i += 1
            continue
        if i + 1 >= len(raw):
            decoded.append(ord("\\"))
            i += 1
            continue
        nxt = raw[i + 1]
        if nxt == "\\":
            decoded.append(ord("\\"))
            i += 2
            continue
        if nxt == "x" and i + 3 < len(raw):
            hex_pair = raw[i + 2 : i + 4]
            if re.fullmatch(r"[0-9A-Fa-f]{2}", hex_pair):
                decoded.append(int(hex_pair, 16))
                i += 4
                continue
        decoded.append(ord("\\"))
        i += 1
    return decoded.decode("utf-8", "surrogateescape")


def stored_rel_path(path: str) -> str:
    normalized = normalize_rel_path(path)
    return encode_path_text(normalized) if normalized else ""


def operational_rel_path(path: str) -> str:
    return normalize_rel_path(decode_path_text(path))


def external_rel_path(path: str) -> str:
    return operational_rel_path(path)


def repo_relative_target_path(root: Path, raw_target: str) -> str:
    if not raw_target:
        return ""

    normalized = raw_target.replace("\\", "/").strip()
    if not normalized:
        return ""

    try:
        candidate = Path(normalized)
        if candidate.is_absolute():
            resolved = candidate.resolve(strict=False)
        else:
            resolved = (root / candidate).resolve(strict=False)
    except (OSError, RuntimeError, ValueError):
        return ""

    try:
        return resolved.relative_to(root.resolve()).as_posix()
    except ValueError:
        return ""


def sanitize_json_value(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            safe_output_text(key) if isinstance(key, str) else str(key): sanitize_json_value(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [sanitize_json_value(item) for item in value]
    if isinstance(value, tuple):
        return [sanitize_json_value(item) for item in value]
    if isinstance(value, bytes):
        return value.decode("utf-8", "backslashreplace")
    if isinstance(value, str):
        return safe_output_text(value)
    return value


def decode_git_output(raw: bytes) -> str:
    return raw.decode("utf-8", "surrogateescape")


# JSONL imports must canonicalize repo-relative path columns through the same
# byte-safe storage encoding used by live Git ingestion.
IMPORTED_STORED_REL_PATH_COLUMNS: dict[str, dict[str, bool]] = {
    "cycles": {"selected_path": False},
    "file_events": {"path": False},
    "file_paths": {"path": True},
    "file_snapshots": {"path": True},
    "files": {"canonical_path": True, "current_path": True},
    "git_file_changes": {"path": True, "old_path": False},
    "selection_candidates": {"path": True},
    "selection_runs": {"selected_path": False},
    "worktree_snapshot_paths": {
        "path": True,
        "old_path": False,
        "path_hmac": False,
        "old_path_hmac": False,
    },
}


def normalize_imported_stored_rel_path_payload(table: str, payload: dict[str, Any]) -> dict[str, Any]:
    columns = IMPORTED_STORED_REL_PATH_COLUMNS.get(table)
    if not columns:
        return payload
    updated = dict(payload)
    for column, required in columns.items():
        if column not in updated:
            continue
        value = updated[column]
        if value is None:
            if required:
                raise ValueError(f"missing_repo_relative_path:{column}")
            continue
        if not isinstance(value, str):
            raise ValueError(f"invalid_repo_relative_path_type:{column}")
        if not value:
            if required:
                raise ValueError(f"empty_repo_relative_path:{column}")
            updated[column] = None
            continue
        normalized = stored_rel_path(external_rel_path(value))
        if normalized:
            updated[column] = normalized
            continue
        if required:
            raise ValueError(f"invalid_repo_relative_path:{column}")
        updated[column] = None
    return updated


def worktree_snapshot_untracked_files_mode(raw: str | None = None) -> str:
    requested = str(raw).strip().lower() if has_meaningful_value(raw) else ""
    if not requested:
        requested = str(os.environ.get(WORKTREE_SNAPSHOT_UNTRACKED_FILES_ENV, "")).strip().lower()
    if requested not in WORKTREE_SNAPSHOT_UNTRACKED_MODES:
        return "no"
    return requested


def worktree_snapshot_path_is_sensitive(path: str) -> bool:
    normalized = normalize_rel_path(path)
    if not normalized:
        return False
    normalized_lower = normalized.lower()
    parts = normalized_lower.split("/")
    if any(normalized_lower.startswith(prefix) for prefix in WORKTREE_RUNTIME_MESSAGE_ARTIFACT_PATH_PREFIXES):
        return True
    for part in SENSITIVE_WORKTREE_PATH_PARTS:
        if part in parts:
            return True
    for suffix in SENSITIVE_WORKTREE_PATH_SUFFIXES:
        if normalized_lower.endswith(suffix):
            return True
    for fragment in SENSITIVE_WORKTREE_PATH_FRAGMENTS:
        if fragment in normalized_lower:
            return True
    return False


def is_runtime_artifact_path(path: str) -> bool:
    normalized = normalize_rel_path(path)
    if not normalized:
        return False
    normalized_lower = normalized.lower()
    return normalized_lower == "runtime" or normalized_lower.startswith("runtime/")


def worktree_snapshot_path_class(status_code: str, *, is_old: bool = False) -> str:
    status_code = str(status_code or "")[:2]
    if len(status_code) != 2:
        return WORKTREE_PATH_CLASS_TRACKED
    if status_code == "??":
        return WORKTREE_PATH_CLASS_UNTRACKED
    if "R" in status_code or "C" in status_code:
        return WORKTREE_PATH_CLASS_RENAMED_OLD if is_old else WORKTREE_PATH_CLASS_RENAMED_NEW
    return WORKTREE_PATH_CLASS_TRACKED


def json_dumps(value: Any) -> str:
    return json.dumps(
        sanitize_json_value(value),
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        default=str,
    )


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_text(text: str) -> str:
    return sha256_bytes(text.encode("utf-8", "surrogateescape"))


def contributor_identity_hash(name: str, email: str) -> str:
    if not name and not email:
        return ""
    return CONTRIBUTOR_HASH_PREFIX + sha256_text(f"name={name}\0email={email}")


def commit_subject_hash(subject: str) -> str:
    return COMMIT_SUBJECT_HASH_PREFIX + sha256_text(subject)


def commit_subject_summary(subject: str | None, subject_hash: Any, subject_length: Any, subject_included: Any) -> dict[str, Any]:
    included = 1 if parse_bool_int(str(subject_included) if subject_included is not None else None) == 1 else 0
    raw_subject = subject if isinstance(subject, str) else ""
    derived_hash = str(subject_hash or "")
    if not derived_hash and (raw_subject or subject is not None):
        derived_hash = commit_subject_hash(raw_subject)
    derived_length = subject_length
    if derived_length is None and (raw_subject or subject is not None):
        derived_length = len(raw_subject)
    return {
        "subject": raw_subject if included else None,
        "subject_hash": derived_hash or None,
        "subject_length": int(derived_length) if derived_length is not None else None,
        "subject_included": included,
    }


def local_git_source_payload(
    author_hash: str | None,
    committer_hash: str | None,
    subject: str,
    *,
    include_commit_subjects: bool,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "author_identity_hash": author_hash or None,
        "committer_identity_hash": committer_hash or None,
    }
    payload.update(
        commit_subject_summary(
            subject if include_commit_subjects else None,
            commit_subject_hash(subject),
            len(subject),
            1 if include_commit_subjects else 0,
        )
    )
    return payload


def source_record_storage_path(root: Path, source_kind: str, value: str) -> str:
    if not value or identity_value_is_redacted(value):
        return value
    if source_kind not in SOURCE_RECORD_PATH_HMAC_KINDS:
        return value
    return artifact_path_hmac(root, value)


def source_record_storage_uri(root: Path, source_kind: str, value: str) -> str:
    if not value or identity_value_is_redacted(value):
        return value
    if source_kind not in SOURCE_RECORD_PATH_HMAC_KINDS:
        return value
    return artifact_path_hmac(root, value)


def sanitize_upkeeper_log_parsed(parsed: dict[str, Any]) -> dict[str, Any]:
    return filter_upkeeper_log_fields(parsed, UPKEEPER_LOG_SOURCE_SAFE_KEYS)


def sanitize_quota_log_fields(root: Path | None, fields: dict[str, Any]) -> dict[str, Any]:
    sanitized = filter_upkeeper_log_fields(fields, UPKEEPER_LOG_SOURCE_SAFE_KEYS)
    if root is None:
        return sanitized
    for key, value in fields.items():
        if key in {"timestamp", "level", "event"} or not has_meaningful_value(value):
            continue
        normalized_key = normalized_metadata_key(key)
        hashed = ""
        if normalized_key in {"source", "source_uri"} or cycle_start_key_is_path_like(normalized_key):
            hashed = artifact_path_hmac(root, str(value))
        elif normalized_key.endswith("limit_id") or normalized_key.endswith("limit_name"):
            hashed = metadata_value_hmac(root, normalized_key, str(value))
        if hashed:
            sanitized[f"{key}_hmac"] = hashed
    return sanitized


def sanitize_nonverbose_upkeeper_log_fields(root: Path | None, fields: dict[str, Any]) -> dict[str, Any]:
    event = str(fields.get("event", "")).strip()
    if event == "cycle.start":
        return sanitize_cycle_start_fields(root, fields) if root is not None else filter_upkeeper_log_fields(fields, CYCLE_START_SAFE_KEYS)
    if event.startswith("quota."):
        return sanitize_quota_log_fields(root, fields)
    return fields


def sanitize_upkeeper_log_raw_text(
    root: Path | None,
    raw_text: str | None,
    parsed: dict[str, Any] | None = None,
) -> str | None:
    if not isinstance(raw_text, str) or not raw_text.strip():
        return raw_text
    if verbose_metadata_enabled():
        return raw_text
    parsed_fields = parsed if isinstance(parsed, dict) else parse_upkeeper_log_line(raw_text)
    if not isinstance(parsed_fields, dict):
        return None
    sanitized_fields = sanitize_nonverbose_upkeeper_log_fields(root, parsed_fields)
    if sanitized_fields is parsed_fields:
        return raw_text
    return render_upkeeper_log_line(sanitized_fields)


def sanitize_source_record_payload(
    payload: dict[str, Any],
    *,
    root: Path | None = None,
) -> dict[str, Any]:
    updated = dict(payload)
    source_kind = str(updated.get("source_kind") or "")
    if root is not None and isinstance(updated.get("source_path"), str):
        updated["source_path"] = source_record_storage_path(root, source_kind, updated["source_path"])
    if root is not None and isinstance(updated.get("source_uri"), str):
        updated["source_uri"] = source_record_storage_uri(root, source_kind, updated["source_uri"])
    if source_kind != "local_git":
        if source_kind == "upkeeper_log":
            parsed_json = updated.get("parsed_json")
            parsed_payload: dict[str, Any] | None = None
            if isinstance(parsed_json, str) and parsed_json.strip():
                try:
                    parsed = json.loads(parsed_json)
                except (TypeError, json.JSONDecodeError):
                    parsed = None
                if isinstance(parsed, dict):
                    parsed_payload = parsed
                    updated["parsed_json"] = json_dumps(sanitize_upkeeper_log_parsed(parsed))
            raw_text = updated.get("raw_text")
            if isinstance(raw_text, str):
                updated["raw_text"] = sanitize_upkeeper_log_raw_text(root, raw_text, parsed_payload)
        return updated
    parsed_json = updated.get("parsed_json")
    if not isinstance(parsed_json, str) or not parsed_json.strip():
        return updated
    try:
        parsed = json.loads(parsed_json)
    except (TypeError, json.JSONDecodeError):
        return updated
    if not isinstance(parsed, dict):
        return updated
    normalized = dict(parsed)
    summary = commit_subject_summary(
        normalized.get("subject") if isinstance(normalized.get("subject"), str) else None,
        normalized.get("subject_hash"),
        normalized.get("subject_length"),
        normalized.get("subject_included"),
    )
    normalized["subject_hash"] = summary["subject_hash"]
    normalized["subject_length"] = summary["subject_length"]
    normalized["subject_included"] = summary["subject_included"]
    if summary["subject_included"] == 1 and summary["subject"] is not None:
        normalized["subject"] = summary["subject"]
    else:
        normalized.pop("subject", None)
    updated["parsed_json"] = json_dumps(normalized)
    return updated


def configured_lattice_raw_storage() -> str:
    raw = os.environ.get("UPKEEPER_LATTICE_RAW_STORAGE", DEFAULT_RAW_STORAGE_MODE).strip().lower()
    return raw if raw else DEFAULT_RAW_STORAGE_MODE


def sanitize_git_privacy_payload(table: str, payload: dict[str, Any], *, root: Path | None = None) -> dict[str, Any]:
    if table == "contributors":
        updated = dict(payload)
        identity_hash = str(updated.get("identity_hash") or "")
        name = updated.get("name") if isinstance(updated.get("name"), str) else ""
        email = updated.get("email") if isinstance(updated.get("email"), str) else ""
        if not identity_hash:
            identity_hash = contributor_identity_hash(name, email)
        updated["identity_hash"] = identity_hash or None
        pii_included = 1 if parse_bool_int(str(updated.get("pii_included")) if updated.get("pii_included") is not None else None) == 1 else 0
        updated["pii_included"] = pii_included
        if pii_included != 1:
            updated["name"] = None
            updated["email"] = None
            updated["github_login"] = None
        return updated
    if table == "git_commits":
        updated = dict(payload)
        updated.update(
            commit_subject_summary(
                updated.get("subject") if isinstance(updated.get("subject"), str) else None,
                updated.get("subject_hash"),
                updated.get("subject_length"),
                updated.get("subject_included"),
            )
        )
        return updated
    if table == "source_records":
        return sanitize_source_record_payload(payload, root=root)
    return payload


def current_lattice_raw_storage() -> str:
    raw = configured_lattice_raw_storage()
    return raw if raw in RAW_STORAGE_COMPAT_MODES else DEFAULT_RAW_STORAGE_MODE


def effective_lattice_raw_storage(raw_storage_mode: str | None = None) -> str:
    mode = (raw_storage_mode or current_lattice_raw_storage()).strip().lower()
    if mode == "debug":
        return "full"
    return mode if mode in RAW_STORAGE_MODES else DEFAULT_RAW_STORAGE_MODE


def source_record_parsed_allowed(source_kind: str, raw_ref: str, parse_status: str, *, raw_storage_mode: str | None = None) -> bool:
    mode = effective_lattice_raw_storage(raw_storage_mode)
    if mode == "full":
        return True
    if mode == "none":
        return False
    if source_kind == "recovery" and parse_status == "spooled_lattice_unavailable":
        return True
    key = (source_kind, "rejected" if source_kind == "transcript" and parse_status == "rejected" else "")
    if source_kind == "recovery":
        key = (source_kind, raw_ref)
    if mode == "minimal":
        return key in MINIMAL_PARSED_SOURCE_RECORDS
    return key in LIMITED_PARSED_SOURCE_RECORDS


def normalize_source_record_parsed(
    source_kind: str,
    raw_ref: str,
    parse_status: str,
    parsed: Any,
    *,
    raw_storage_mode: str | None = None,
) -> Any:
    if parsed is None:
        return None
    if not source_record_parsed_allowed(source_kind, raw_ref, parse_status, raw_storage_mode=raw_storage_mode):
        return None
    if source_kind == "upkeeper_log" and isinstance(parsed, dict):
        return sanitize_upkeeper_log_parsed(parsed)
    if source_kind != "local_git" or not isinstance(parsed, dict):
        return parsed
    normalized = dict(parsed)
    keep_subject = effective_lattice_raw_storage(raw_storage_mode) == "full"
    summary = commit_subject_summary(
        normalized.get("subject") if keep_subject and isinstance(normalized.get("subject"), str) else None,
        normalized.get("subject_hash"),
        normalized.get("subject_length"),
        normalized.get("subject_included") if keep_subject else 0,
    )
    normalized["subject_hash"] = summary["subject_hash"]
    normalized["subject_length"] = summary["subject_length"]
    normalized["subject_included"] = summary["subject_included"]
    normalized.pop("subject", None)
    if summary["subject"] is not None:
        normalized["subject"] = summary["subject"]
    return normalized


def summarize_lattice_unavailable_payload(payload: dict[str, Any], raw_line: str) -> dict[str, Any]:
    summary: dict[str, Any] = {"raw_sha256": sha256_text(raw_line)}
    cycle_id = payload.get("cycle_id")
    if isinstance(cycle_id, str) and cycle_id.strip():
        summary["cycle_id"] = cycle_id
    run_hash = payload.get("run_hash")
    if isinstance(run_hash, str) and run_hash.strip():
        summary["run_hash"] = run_hash
    observed_epoch = payload.get("observed_epoch")
    try:
        if observed_epoch is not None:
            summary["observed_epoch"] = int(observed_epoch)
    except (TypeError, ValueError):
        pass
    db_path = payload.get("db_path")
    if isinstance(db_path, str) and db_path:
        summary["db_path_sha256"] = sha256_text(db_path)
    detail = payload.get("detail")
    if isinstance(detail, str) and detail:
        summary["detail_sha256"] = sha256_text(detail)
    return summary


def normalized_source_record_parsed_json(
    source_kind: str,
    raw_ref: str,
    parse_status: str,
    parsed_json: str | None,
    *,
    raw_storage_mode: str | None = None,
) -> str | None:
    if not isinstance(parsed_json, str) or not parsed_json.strip():
        return None
    try:
        parsed = json.loads(parsed_json)
    except (TypeError, json.JSONDecodeError):
        return parsed_json if effective_lattice_raw_storage(raw_storage_mode) == "full" else None
    normalized = normalize_source_record_parsed(
        source_kind,
        raw_ref,
        parse_status,
        parsed,
        raw_storage_mode=raw_storage_mode,
    )
    return json_dumps(normalized) if normalized is not None else None


def sanitize_imported_source_record_row(
    payload: dict[str, Any],
    *,
    root: Path,
    redact_raw: bool,
    raw_storage_mode: str | None = None,
) -> dict[str, Any]:
    filtered = sanitize_source_record_payload(payload, root=root)
    filtered["raw_text"] = (
        filtered.get("raw_text")
        if effective_lattice_raw_storage(raw_storage_mode) == "full" and not redact_raw
        else None
    )
    filtered["parsed_json"] = normalized_source_record_parsed_json(
        str(filtered.get("source_kind") or ""),
        str(filtered.get("raw_ref") or ""),
        str(filtered.get("parse_status") or "parsed"),
        filtered.get("parsed_json") if isinstance(filtered.get("parsed_json"), str) else None,
        raw_storage_mode=raw_storage_mode,
    )
    return filtered


def raw_repo_identity_enabled() -> bool:
    raw = os.environ.get(UPKEEPER_RAW_REPO_IDENTITY_ENV, "").strip()
    if raw:
        return parse_bool_int(raw) == 1
    return effective_lattice_raw_storage() == "full"


def repo_identity_context(root: Path, info: dict[str, str] | None = None) -> tuple[str, str, str]:
    info = info or repo_git_info(root)
    return (str(root.resolve()), str(info.get("git_common_dir") or ""), str(info.get("remote_url") or ""))


def repo_identity_hmac_key(context: tuple[str, str, str], purpose: str) -> bytes:
    root_value, git_common_dir, remote_seed = context
    material = f"{root_value}\0{git_common_dir}\0{remote_seed}\0{purpose}"
    return hashlib.sha256(material.encode("utf-8", "surrogateescape")).digest()


def repo_identity_value_hmac(context: tuple[str, str, str], namespace: str, value: str, prefix: str) -> str:
    if not value:
        return ""
    material = f"{namespace}\0{value}"
    digest = hmac.digest(repo_identity_hmac_key(context, "repo-identity"), material.encode("utf-8", "surrogateescape"), "sha256").hex()
    return prefix + digest


def git_common_dir_path(root: Path) -> str:
    common = git_output(root, ["rev-parse", "--path-format=absolute", "--git-common-dir"], "")
    if not common:
        common = git_output(root, ["rev-parse", "--git-common-dir"], "")
    if not common:
        return ""
    path = Path(common)
    if not path.is_absolute():
        path = root / path
    try:
        return str(path.resolve(strict=False))
    except OSError:
        return str(path.absolute())


def identity_value_is_redacted(value: str) -> bool:
    if not value:
        return False
    prefixes = (
        REDACTED_PATH_PREFIX,
        PASS_RESULT_PATH_HMAC_PREFIX,
        METADATA_HMAC_PREFIX,
        CONTENT_HMAC_PREFIX,
        CONTRIBUTOR_HASH_PREFIX,
        COMMIT_SUBJECT_HASH_PREFIX,
        BRANCH_HMAC_PREFIX,
        REMOTE_HMAC_PREFIX,
        SSH_REMOTE_HMAC_PREFIX,
        LOCAL_REMOTE_HMAC_PREFIX,
    )
    return value.startswith(prefixes)


def remote_is_ssh(raw: str) -> bool:
    lowered = raw.lower()
    if lowered.startswith(("ssh://", "git+ssh://")):
        return True
    return bool(re.match(r"^[^/\s@]+@[^:\s]+:.+", raw))


def remote_is_local(raw: str) -> bool:
    lowered = raw.lower()
    if lowered.startswith("file://"):
        return True
    if raw.startswith(("/", "./", "../", "~")):
        return True
    return bool(re.match(r"^[A-Za-z]:[\\/]", raw))


def protected_repo_path(context: tuple[str, str, str], value: str) -> str:
    if not value or identity_value_is_redacted(value):
        return value
    if raw_repo_identity_enabled():
        return value
    return repo_identity_value_hmac(context, "path", value, PASS_RESULT_PATH_HMAC_PREFIX)


def protected_branch_name(context: tuple[str, str, str], value: str) -> str:
    if not value or identity_value_is_redacted(value):
        return value
    if raw_repo_identity_enabled():
        return value
    return repo_identity_value_hmac(context, "branch_name", value, BRANCH_HMAC_PREFIX)


def protected_remote_url(context: tuple[str, str, str], value: str) -> str:
    if not value:
        return ""
    value = sanitize_remote_url(value)
    if identity_value_is_redacted(value):
        return value
    if raw_repo_identity_enabled():
        if remote_is_ssh(value):
            return repo_identity_value_hmac(context, "ssh_remote_url", value, SSH_REMOTE_HMAC_PREFIX)
        if remote_is_local(value):
            return repo_identity_value_hmac(context, "local_remote_url", value, LOCAL_REMOTE_HMAC_PREFIX)
        return value
    return repo_identity_value_hmac(context, "remote_url", value, REMOTE_HMAC_PREFIX)


def protected_origin_url_hash(context: tuple[str, str, str], value: str) -> str:
    if not value:
        return ""
    if identity_value_is_redacted(value):
        return value
    value = sanitize_remote_url(value)
    return repo_identity_value_hmac(context, "origin_url", value, REMOTE_HMAC_PREFIX)


def sanitize_repository_payload(payload: dict[str, Any], context: tuple[str, str, str]) -> dict[str, Any]:
    updated = dict(payload)
    for key in ("root_path", "first_seen_root_path", "current_root_path", "working_tree_path", "git_common_dir"):
        if isinstance(updated.get(key), str):
            updated[key] = protected_repo_path(context, updated[key])
    if isinstance(updated.get("branch_name"), str):
        updated["branch_name"] = protected_branch_name(context, updated["branch_name"])
    remote_value = updated.get("remote_url") if isinstance(updated.get("remote_url"), str) else ""
    if remote_value:
        updated["remote_url"] = protected_remote_url(context, remote_value)
    origin_value = updated.get("origin_url_hash") if isinstance(updated.get("origin_url_hash"), str) else ""
    if remote_value:
        updated["origin_url_hash"] = protected_origin_url_hash(context, remote_value)
    elif origin_value and not identity_value_is_redacted(origin_value):
        updated["origin_url_hash"] = repo_identity_value_hmac(context, "legacy_origin_url_hash", origin_value, REMOTE_HMAC_PREFIX)
    return updated


def sanitize_repo_alias_payload(payload: dict[str, Any], context: tuple[str, str, str]) -> dict[str, Any]:
    updated = dict(payload)
    alias_kind = str(updated.get("alias_kind") or "")
    alias_value = updated.get("alias_value") if isinstance(updated.get("alias_value"), str) else ""
    if not alias_value:
        return updated
    if alias_kind in {"root_path", "git_common_dir"}:
        updated["alias_value"] = protected_repo_path(context, alias_value)
    elif alias_kind == "remote_url_hash":
        if identity_value_is_redacted(alias_value):
            updated["alias_value"] = alias_value
        else:
            updated["alias_value"] = repo_identity_value_hmac(context, "remote_url_hash", alias_value, REMOTE_HMAC_PREFIX)
    return updated


def scrub_repo_identity_rows(conn: sqlite3.Connection, repo_id: int, context: tuple[str, str, str]) -> None:
    row = conn.execute(
        """
        select root_path, first_seen_root_path, current_root_path, working_tree_path, git_common_dir, branch_name, remote_url, origin_url_hash
        from repositories
        where repo_id=?
        """,
        (repo_id,),
    ).fetchone()
    if row:
        updated = sanitize_repository_payload(dict(row), context)
        conn.execute(
            """
            update repositories
            set root_path=?, first_seen_root_path=?, current_root_path=?, working_tree_path=?,
                git_common_dir=?, branch_name=?, remote_url=?, origin_url_hash=?
            where repo_id=?
            """,
            (
                updated.get("root_path"),
                updated.get("first_seen_root_path"),
                updated.get("current_root_path"),
                updated.get("working_tree_path"),
                updated.get("git_common_dir"),
                updated.get("branch_name"),
                updated.get("remote_url"),
                updated.get("origin_url_hash"),
                repo_id,
            ),
        )
    for row in conn.execute("select repo_alias_id, alias_kind, alias_value from repo_aliases where repo_id=?", (repo_id,)):
        updated = sanitize_repo_alias_payload(dict(row), context)
        new_value = updated.get("alias_value")
        if not isinstance(new_value, str) or new_value == row["alias_value"]:
            continue
        duplicate = conn.execute(
            "select repo_alias_id from repo_aliases where repo_id=? and alias_kind=? and alias_value=?",
            (repo_id, row["alias_kind"], new_value),
        ).fetchone()
        if duplicate and int(duplicate["repo_alias_id"]) != int(row["repo_alias_id"]):
            conn.execute("delete from repo_aliases where repo_alias_id=?", (int(row["repo_alias_id"]),))
            continue
        conn.execute("update repo_aliases set alias_value=? where repo_alias_id=?", (new_value, int(row["repo_alias_id"])))
    for table, pk in (("cycles", "cycle_pk"), ("worktree_snapshots", "worktree_snapshot_id")):
        for row in conn.execute(f"select {pk}, branch_name from {table} where repo_id=? and branch_name is not null", (repo_id,)):
            branch_name = row["branch_name"] if isinstance(row["branch_name"], str) else ""
            new_branch = protected_branch_name(context, branch_name)
            if new_branch != branch_name:
                conn.execute(f"update {table} set branch_name=? where {pk}=?", (new_branch, int(row[pk])))


def scrub_source_record_rows(conn: sqlite3.Connection, root: Path, repo_id: int) -> None:
    for row in conn.execute(
        """
        select source_id, source_kind, source_path, source_uri
        from source_records
        where repo_id=? and (source_path is not null or source_uri is not null)
        """,
        (repo_id,),
    ):
        source_kind = str(row["source_kind"] or "")
        source_path = row["source_path"] if isinstance(row["source_path"], str) else ""
        updated_path = source_record_storage_path(root, source_kind, source_path)
        source_uri = row["source_uri"] if isinstance(row["source_uri"], str) else ""
        updated_uri = source_record_storage_uri(root, source_kind, source_uri)
        if updated_path != source_path or updated_uri != source_uri:
            conn.execute(
                "update source_records set source_path=?, source_uri=? where source_id=?",
                (updated_path, updated_uri, int(row["source_id"])),
            )


def verbose_metadata_enabled() -> bool:
    return parse_bool_int(os.environ.get(UPKEEPER_VERBOSE_METADATA_ENV, "")) == 1


def pass_result_debug_storage_enabled(raw_storage_mode: str | None = None) -> bool:
    mode = (raw_storage_mode or current_lattice_raw_storage()).strip().lower()
    return mode in PASS_RESULT_DEBUG_STORAGE_VALUES


def pass_result_hmac_key(root: Path) -> bytes:
    override = os.environ.get("UPKEEPER_LATTICE_REDACTION_KEY", "")
    if override:
        return override.encode("utf-8", "surrogateescape")
    root = root.resolve()
    info = repo_git_info(root)
    return repo_identity_hmac_key(repo_identity_context(root, info), "upkeeper-pass-result")


def pass_result_path_hmac(root: Path, path: str) -> str:
    normalized = normalize_rel_path(path)
    if not normalized:
        return ""
    digest = hmac.digest(pass_result_hmac_key(root), normalized.encode("utf-8", "surrogateescape"), "sha256").hex()
    return PASS_RESULT_PATH_HMAC_PREFIX + digest


def metadata_value_hmac(root: Path, key: str, value: str) -> str:
    material = f"{key}\0{value}"
    digest = hmac.digest(pass_result_hmac_key(root), material.encode("utf-8", "surrogateescape"), "sha256").hex()
    return METADATA_HMAC_PREFIX + digest


def content_value_hmac(root: Path, value: str) -> str:
    if not value or value in {"none", "unknown", "missing", "unavailable", "clean", "not_regular"}:
        return value or "unknown"
    material = f"content\0{value}"
    digest = hmac.digest(pass_result_hmac_key(root), material.encode("utf-8", "surrogateescape"), "sha256").hex()
    return CONTENT_HMAC_PREFIX + digest


def canonical_artifact_identity(root: Path, raw_path: str) -> str:
    if not raw_path:
        return ""
    path = Path(raw_path).expanduser()
    normalized = Path(os.path.normpath(str(path.absolute())))
    try:
        relative = normalized.relative_to(root)
    except ValueError:
        return normalized.as_posix()
    relative_text = normalize_rel_path(relative.as_posix())
    return relative_text or "."


def artifact_path_hmac(root: Path, raw_path: str) -> str:
    normalized = canonical_artifact_identity(root, raw_path)
    if not normalized:
        return ""
    digest = hmac.digest(pass_result_hmac_key(root), normalized.encode("utf-8", "surrogateescape"), "sha256").hex()
    return PASS_RESULT_PATH_HMAC_PREFIX + digest


def artifact_storage_path(root: Path, raw_path: str) -> str:
    return artifact_path_hmac(root, raw_path)


def artifact_retention_class(artifact_kind: str) -> str:
    return ARTIFACT_RETENTION_CLASSES.get(artifact_kind, "durable")


def artifact_details_payload(artifact_kind: str, details: Any = None) -> dict[str, Any]:
    payload: dict[str, Any] = {"retention_class": artifact_retention_class(artifact_kind)}
    if isinstance(details, dict):
        for key, value in details.items():
            if has_meaningful_value(value):
                payload[key] = value
    return payload


def normalized_metadata_key(key: str) -> str:
    return key.strip().lower().replace("-", "_")


def cycle_start_key_is_path_like(key: str) -> bool:
    return key in CYCLE_START_PATH_KEYS or "path" in key


def cycle_start_key_should_hash(key: str) -> bool:
    if cycle_start_key_is_path_like(key):
        return True
    return any(fragment in key for fragment in CYCLE_START_HASH_KEY_FRAGMENTS)


def sanitize_cycle_start_fields(root: Path, fields: dict[str, Any]) -> dict[str, Any]:
    sanitized: dict[str, Any] = {}
    verbose = verbose_metadata_enabled()
    for key, value in fields.items():
        if key == "func" or not has_meaningful_value(value):
            continue
        normalized_key = normalized_metadata_key(key)
        if normalized_key in CYCLE_START_SAFE_KEYS:
            sanitized[key] = value
            continue
        if verbose:
            sanitized[key] = value
            continue
        if cycle_start_key_should_hash(normalized_key):
            if cycle_start_key_is_path_like(normalized_key):
                hashed = pass_result_path_hmac(root, str(value))
            else:
                hashed = metadata_value_hmac(root, normalized_key, str(value))
            if hashed:
                sanitized[f"{key}_hmac"] = hashed
    return sanitized


def render_upkeeper_log_line(fields: dict[str, Any]) -> str:
    body_parts: list[str] = []
    event = str(fields.get("event", "")).strip()
    if event:
        body_parts.append(event)
    for key, value in fields.items():
        if key in {"timestamp", "level", "event"} or not has_meaningful_value(value):
            continue
        body_parts.append(f"{key}={shlex.quote(str(value))}")
    line_parts: list[str] = []
    timestamp = str(fields.get("timestamp", "")).strip()
    level = str(fields.get("level", "")).strip()
    if timestamp:
        line_parts.append(timestamp)
    if level:
        line_parts.append(f"[{level}]")
    if body_parts:
        line_parts.append(" ".join(body_parts))
    return " ".join(line_parts).strip()


def print_json(value: Any) -> None:
    print(json.dumps(sanitize_json_value(value), sort_keys=True, indent=2))


def redirect_stdout_to_devnull() -> None:
    devnull_fd = None
    try:
        devnull_fd = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull_fd, sys.stdout.fileno())
    except OSError:
        pass
    finally:
        if devnull_fd is not None:
            try:
                os.close(devnull_fd)
            except OSError:
                pass


class LatticeCommandError(Exception):
    def __init__(self, message: str, code: int, *, emitted: bool) -> None:
        super().__init__(message)
        self.code = code
        self.emitted = emitted


def raise_command_error(message: str, code: int, *, emit: bool = True) -> None:
    if emit:
        print(f"upkeeper_lattice: {message}", file=sys.stderr)
    raise LatticeCommandError(message, code, emitted=emit)


def fail(message: str, code: int) -> None:
    raise_command_error(message, code)


def run_git(
    root: Path,
    args: list[str],
    *,
    text: bool = True,
    check: bool = True,
    errors: str = "backslashreplace",
) -> Any:
    try:
        return subprocess.run(
            ["git", "-C", str(root), *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=text,
            errors=errors if text else None,
            check=check,
        )
    except FileNotFoundError:
        raise SystemExit(EXIT_GIT_UNAVAILABLE)
    except (UnicodeEncodeError, UnicodeError, ValueError):
        if check:
            raise SystemExit(EXIT_GIT_UNAVAILABLE)
        return None
    except subprocess.CalledProcessError:
        if check:
            raise
        return None


def git_output(root: Path, args: list[str], default: str = "", strip: bool = True) -> str:
    try:
        result = run_git(root, args, text=True, check=True)
        return result.stdout.strip() if strip else result.stdout
    except (subprocess.CalledProcessError, SystemExit):
        return default


def parse_git_porcelain_v1_z_entries(raw: bytes) -> list[tuple[str, str, str | None]]:
    entries: list[tuple[str, str, str | None]] = []
    parts = raw.split(b"\0") if raw else []
    i = 0
    while i < len(parts):
        item = parts[i]
        i += 1
        # Git porcelain v1 -z uses the first two bytes as XY status, and a
        # leading space is meaningful for unstaged-only worktree changes.
        if not item or len(item) < 4 or item[2:3] != b" ":
            continue
        status_code = decode_git_output(item[:2])
        path = decode_git_output(item[3:])
        old_path = None
        if status_code[0] in {"R", "C"} or status_code[1] in {"R", "C"}:
            if i < len(parts):
                old_path = decode_git_output(parts[i]) or None
                i += 1
        entries.append((status_code, path, old_path))
    return entries


def git_porcelain_status_for_path(root: Path, rel_path: str) -> str:
    rel_path = operational_rel_path(rel_path)
    if has_surrogate_codepoint(rel_path):
        return ""
    try:
        raw = subprocess.check_output(
            ["git", "-C", str(root), "status", "--porcelain=v1", "-z", "--", rel_path],
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError, UnicodeEncodeError, UnicodeError, ValueError):
        return ""
    entries = parse_git_porcelain_v1_z_entries(raw)
    return entries[0][0] if entries else ""


def stored_git_status_code(status_code: str) -> str:
    if len(status_code) < 2:
        return "clean"
    return status_code[:2].replace(" ", "_")


def inside_git_repo(root: Path) -> bool:
    return git_output(root, ["rev-parse", "--is-inside-work-tree"]) == "true"


def default_root() -> Path:
    return Path(os.environ.get("UPKEEPER_ROOT", os.getcwd())).resolve()


def default_db_path(root: Path) -> Path:
    raw = os.environ.get("UPKEEPER_LATTICE_DB")
    if raw:
        path = Path(raw).expanduser()
        return path.absolute() if path.is_absolute() else (root / path).absolute()
    return (root / "runtime/upkeeper-lattice/lattice.sqlite3").absolute()


def normalize_db_path(raw: str | None, root: Path) -> Path:
    if raw:
        path = Path(raw).expanduser()
        return path.absolute() if path.is_absolute() else (root / path).absolute()
    return default_db_path(root)


def path_under(path: Path, parent: Path) -> bool:
    try:
        path_abs = path.absolute()
        parent_abs = parent.absolute()
        return os.path.commonpath([str(path_abs), str(parent_abs)]) == str(parent_abs)
    except ValueError:
        return False


def has_forbidden_symlink(path: Path, base: Path) -> bool:
    try:
        rel = path.absolute().relative_to(base.absolute())
    except ValueError:
        return False
    cursor = base.absolute()
    for part in rel.parts:
        cursor = cursor / part
        try:
            st = cursor.lstat()
        except OSError:
            break
        if stat.S_ISLNK(st.st_mode):
            return True
    return False


def validate_lattice_output_path(
    root: Path,
    raw_output: str | Path,
    *,
    allow_existing: bool = False,
    journal_mode: str = "delete",
    db_path: Path | None = None,
    allow_outside_runtime: bool = False,
) -> Path:
    output = Path(raw_output).expanduser()
    output = output.absolute() if output.is_absolute() else (Path.cwd() / output).absolute()
    runtime_root = (root / "runtime").absolute()
    if not path_under(output, runtime_root) and not allow_outside_runtime:
        fail(f"unsafe output path outside runtime: {output}", EXIT_USAGE)
    if db_path:
        for side_path in db_side_paths(db_path, journal_mode):
            if output == side_path:
                fail(f"unsafe output path collides with database sidecar path: {output}", EXIT_USAGE)
    if output.exists():
        if output.is_dir():
            fail(f"output path is a directory: {output}", EXIT_USAGE)
        if not allow_existing:
            fail(f"output path already exists without overwrite: {output}", EXIT_USAGE)
    if path_under(output, root) and git_path_tracked(root, output):
        fail(f"output path cannot be tracked by git: {output}", EXIT_USAGE)
    return output


def repo_rel_path(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return ""


def git_path_ignored(root: Path, path: Path) -> bool:
    rel = repo_rel_path(root, path)
    if not rel:
        return False
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "check-ignore", "-q", "--no-index", "--", rel],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return result.returncode == 0
    except (FileNotFoundError, UnicodeEncodeError, UnicodeError, ValueError, OSError):
        return False


def normalize_upkeeper_ignore_file(root: Path, raw: str | None = None) -> Path:
    raw = raw or os.environ.get("CODEX_UPKEEPER_IGNORE_FILE") or os.environ.get("UPKEEPER_IGNORE_FILE") or ".upkeeperignore"
    path = Path(raw).expanduser()
    return path.resolve() if path.is_absolute() else (root / path).resolve()


def load_upkeeperignore_patterns(root: Path, raw: str | None = None) -> list[tuple[bool, str]]:
    ignore_file = normalize_upkeeper_ignore_file(root, raw)
    patterns: list[tuple[bool, str]] = []
    try:
        lines = ignore_file.read_text(encoding="utf-8").splitlines()
    except OSError:
        return patterns
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        negated = line.startswith("!")
        if negated:
            line = line[1:].strip()
            if not line:
                continue
        patterns.append((negated, line.replace("\\", "/")))
    return patterns


def upkeeperignore_pattern_matches(path: str, pattern: str) -> bool:
    pattern = pattern.strip()
    if not pattern:
        return False
    anchored = pattern.startswith("/")
    if anchored:
        pattern = pattern.lstrip("/")
    directory_only = pattern.endswith("/")
    if directory_only:
        pattern = pattern.rstrip("/")
    if not pattern:
        return False

    if directory_only:
        if "/" in pattern or anchored:
            return path == pattern or path.startswith(pattern + "/")
        return pattern in path.split("/")

    name = Path(path).name
    if anchored or "/" in pattern:
        return fnmatch.fnmatch(path, pattern)
    return fnmatch.fnmatch(name, pattern) or any(fnmatch.fnmatch(part, pattern) for part in path.split("/"))


def upkeeper_path_ignored(path: str, patterns: list[tuple[bool, str]]) -> bool:
    ignored = False
    for negated, pattern in patterns:
        if upkeeperignore_pattern_matches(path, pattern):
            ignored = not negated
    return ignored


def git_path_tracked(root: Path, path: Path) -> bool:
    rel = repo_rel_path(root, path)
    if not rel:
        return False
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "--error-unmatch", "--", rel],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return result.returncode == 0
    except (FileNotFoundError, UnicodeEncodeError, UnicodeError, ValueError, OSError):
        return False


def git_ignored_paths(root: Path, paths: list[str]) -> set[str]:
    if not paths:
        return set()
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "check-ignore", "-z", "--no-index", "--stdin"],
            input=("\0".join(paths) + "\0").encode("utf-8", "surrogateescape"),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        return set()
    if result.returncode not in (0, 1):
        return set()
    return set(path for path in decode_git_output(result.stdout).split("\0") if path)


def source_safe_parts(rel_path: str) -> list[str] | None:
    rel_path = operational_rel_path(rel_path)
    if has_surrogate_codepoint(rel_path):
        return None
    if not rel_path or rel_path == "." or rel_path.startswith("../") or Path(rel_path).is_absolute():
        return None
    parts = rel_path.split("/")
    if any(part in ("", ".", "..") for part in parts):
        return None
    return parts


def source_safe_real_path(root: Path, rel_path: str) -> Path | None:
    rel_path = operational_rel_path(rel_path)
    try:
        real = (root / rel_path).resolve(strict=True)
        real.relative_to(root.resolve())
        return real
    except (OSError, ValueError, UnicodeEncodeError, UnicodeError):
        return None


def read_fd_sample(file_fd: int, sample_size: int) -> bytes:
    return os.read(file_fd, sample_size)


def read_sample_no_follow(root: Path, parts: list[str], sample_size: int = TEXT_SAMPLE_SIZE) -> bytes | None:
    if sample_size <= 0:
        return b""
    if not parts:
        return b""
    try:
        current = root.resolve()
        current_mode = None
        for index, part in enumerate(parts):
            current = current / part
            st = current.lstat()
            if stat.S_ISLNK(st.st_mode):
                return None
            current_mode = st.st_mode
            if index < len(parts) - 1 and not stat.S_ISDIR(st.st_mode):
                return None
        if not stat.S_ISREG(current_mode or 0):
            return None
        # Read only the requested sample so candidate scans never load the full file.
        with current.open("rb") as handle:
            return read_fd_sample(handle.fileno(), sample_size)
    except OSError:
        return None


def source_safe_file_stat(root: Path, rel_path: str, *, require_text: bool = False) -> tuple[os.stat_result | None, str]:
    rel_path = operational_rel_path(rel_path)
    parts = source_safe_parts(rel_path)
    if parts is None:
        return None, "outside_repo"
    path = root / rel_path
    try:
        st = path.lstat()
    except OSError:
        return None, "missing_at_stat"
    if stat.S_ISLNK(st.st_mode):
        return None, "symlink"
    if source_safe_real_path(root, rel_path) is None:
        return None, "outside_repo"
    if not stat.S_ISREG(st.st_mode):
        return None, "not_regular_file"
    if require_text:
        sample = read_sample_no_follow(root, parts)
        if sample is None or b"\0" in sample:
            return None, "binary_or_unreadable"
    return st, ""


def db_side_paths(db_path: Path, journal_mode: str) -> list[Path]:
    side_paths = [db_path, db_path.with_name(db_path.name + "-journal")]
    if journal_mode.lower() == "wal":
        side_paths.extend([db_path.with_name(db_path.name + "-wal"), db_path.with_name(db_path.name + "-shm")])
    side_paths.extend([db_path.parent / "backups", db_path.parent / "exports", db_path.parent / "recovery"])
    return side_paths


def path_safety(root: Path, db_path: Path, journal_mode: str) -> dict[str, Any]:
    root_abs = root.absolute()
    runtime_root = (root / "runtime").absolute()
    paths = db_side_paths(db_path, journal_mode)
    statuses = []
    unsafe = False
    for path in paths:
        under_runtime = path_under(path, runtime_root)
        under_root = path_under(path, root_abs)
        has_symlink = has_forbidden_symlink(path, root_abs)
        tracked = git_path_tracked(root, path) if under_root else False
        ignored = git_path_ignored(root, path) if under_root else False
        explicit_ok = under_runtime or ignored
        item_unsafe = (
            True
            if not under_root
            else (has_symlink or tracked or (not explicit_ok))
        )
        unsafe = unsafe or item_unsafe
        statuses.append(
            {
                "path": str(path),
                "under_runtime": under_runtime,
                "git_tracked": tracked,
                "git_ignored": ignored,
                "has_symlink": has_symlink,
                "safe": not item_unsafe,
            }
        )
    return {"safe": not unsafe, "paths": statuses}


def check_path_safe(root: Path, db_path: Path, journal_mode: str, allow_unsafe: bool) -> None:
    safety = path_safety(root, db_path, journal_mode)
    if not safety["safe"] and not allow_unsafe:
        print_json({"status": "unsafe_db_path", "db_path": str(db_path), "path_safety": safety})
        raise SystemExit(EXIT_UNSAFE_DB_PATH)


def chmod_private(path: Path, is_dir: bool = False, *, created_by_invocation: bool = False) -> None:
    # Keep directory mode hardening limited to directories this invocation created.
    if is_dir and not created_by_invocation:
        return

    try:
        path.chmod(0o700 if is_dir else 0o600)
    except OSError:
        pass


def connect(
    db_path: Path,
    journal_mode: str,
    *,
    create_parent: bool = False,
    create_if_missing: bool = False,
    emit_errors: bool = True,
) -> sqlite3.Connection:
    try:
        existing = db_path.lstat()
    except FileNotFoundError:
        existing = None
    except OSError as exc:
        raise_command_error(f"DB path not stat-able: {db_path} ({exc})", EXIT_DB_UNAVAILABLE, emit=emit_errors)

    if existing is not None:
        if stat.S_ISLNK(existing.st_mode):
            raise_command_error(f"DB path is a symlink: {db_path}", EXIT_DB_UNAVAILABLE, emit=emit_errors)
        if not stat.S_ISREG(existing.st_mode):
            raise_command_error(f"DB path is not regular: {db_path}", EXIT_DB_UNAVAILABLE, emit=emit_errors)
        if existing.st_uid != os.geteuid():
            raise_command_error(
                f"DB path owner mismatch: {db_path} expected_uid={os.geteuid()} actual_uid={existing.st_uid}",
                EXIT_DB_UNAVAILABLE,
                emit=emit_errors,
            )
        if getattr(existing, "st_nlink", 1) != 1:
            raise_command_error(
                f"DB path has multiple links: {db_path} nlink={existing.st_nlink}",
                EXIT_DB_UNAVAILABLE,
                emit=emit_errors,
            )
    elif not create_if_missing:
        raise_command_error(f"DB path missing: {db_path}", EXIT_DB_UNAVAILABLE, emit=emit_errors)

    if create_parent:
        parent_existed = db_path.parent.exists()
        db_path.parent.mkdir(parents=True, exist_ok=True)
        if not parent_existed:
            chmod_private(db_path.parent, is_dir=True, created_by_invocation=True)
    if not db_path.parent.exists():
        raise_command_error(f"DB parent directory does not exist: {db_path.parent}", EXIT_DB_UNAVAILABLE, emit=emit_errors)
    connect_target = str(db_path)
    connect_kwargs: dict[str, Any] = {}
    if not create_if_missing:
        # Fail closed when callers expect an existing DB so a missing file never
        # becomes a newly created empty SQLite database during open-time races.
        connect_target = f"{db_path.resolve().as_uri()}?mode=rw"
        connect_kwargs["uri"] = True
    try:
        conn = sqlite3.connect(connect_target, **connect_kwargs)
    except sqlite3.Error as exc:
        raise_command_error(f"DB unavailable: {exc}", EXIT_DB_UNAVAILABLE, emit=emit_errors)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute("PRAGMA foreign_keys=ON")
    requested = journal_mode.lower()
    if requested not in {"delete", "wal"}:
        requested = "delete"
    try:
        conn.execute(f"PRAGMA journal_mode={requested}")
    except sqlite3.Error as exc:
        conn.close()
        raise_command_error(
            f"cannot set SQLite journal mode {requested}: {exc}",
            EXIT_DB_UNAVAILABLE,
            emit=emit_errors,
        )
    return conn


def connect_checked(
    root: Path,
    db_path: Path,
    journal_mode: str,
    *,
    allow_unsafe_db: bool,
    create_parent: bool = False,
    create_if_missing: bool = False,
) -> sqlite3.Connection:
    check_path_safe(root, db_path, journal_mode, allow_unsafe_db)
    return connect(
        db_path,
        journal_mode,
        create_parent=create_parent,
        create_if_missing=create_if_missing,
    )


def table_columns(conn: sqlite3.Connection, table: str) -> list[str]:
    return [row["name"] for row in conn.execute(f"PRAGMA table_info({table})")]


def table_primary_key(conn: sqlite3.Connection, table: str) -> str | None:
    for row in conn.execute(f"PRAGMA table_info({table})"):
        if int(row["pk"] or 0) == 1:
            return str(row["name"])
    return None


def dedupe_git_file_changes(conn: sqlite3.Connection) -> int:
    row = conn.execute(
        """
        select count(*) from (
          select 1
          from git_file_changes
          group by repo_id, commit_id, path, coalesce(old_path, ''), coalesce(status, '')
          having count(*) > 1
        )
        """
    ).fetchone()
    duplicate_groups = int(row[0] or 0) if row else 0
    if duplicate_groups:
        conn.execute(
            """
            delete from git_file_changes
            where git_file_change_id not in (
              select min(git_file_change_id)
              from git_file_changes
              group by repo_id, commit_id, path, coalesce(old_path, ''), coalesce(status, '')
            )
            """
        )
    return duplicate_groups


def dedupe_artifact_refs(conn: sqlite3.Connection) -> int:
    row = conn.execute(
        """
        select count(*) from (
          select 1
          from artifact_refs
          group by repo_id, artifact_kind, path, coalesce(sha256, '')
          having count(*) > 1
        )
        """
    ).fetchone()
    duplicate_groups = int(row[0] or 0) if row else 0
    if not duplicate_groups:
        return 0

    duplicate_keys = conn.execute(
        """
        select repo_id, artifact_kind, path, coalesce(sha256, '') as sha_key
        from artifact_refs
        group by repo_id, artifact_kind, path, coalesce(sha256, '')
        having count(*) > 1
        """
    ).fetchall()
    for key in duplicate_keys:
        rows = conn.execute(
            """
            select artifact_id, cycle_pk, source_id, exists_at_record_time, size_bytes,
                   sha256, created_epoch, observed_epoch, retained, details_json
            from artifact_refs
            where repo_id = ? and artifact_kind = ? and path = ?
              and coalesce(sha256, '') = ?
            order by observed_epoch desc, artifact_id desc
            """,
            (key["repo_id"], key["artifact_kind"], key["path"], key["sha_key"]),
        ).fetchall()
        if len(rows) < 2:
            continue
        winner = dict(rows[0])
        winner_id = int(winner["artifact_id"])
        merged_cycle_pk = winner["cycle_pk"]
        merged_source_id = winner["source_id"]
        merged_exists = winner["exists_at_record_time"]
        merged_size = winner["size_bytes"]
        merged_created = winner["created_epoch"]
        merged_observed = winner["observed_epoch"]
        merged_retained = winner["retained"]
        merged_details = winner["details_json"]
        for row_data in rows[1:]:
            if merged_cycle_pk is None and row_data["cycle_pk"] is not None:
                merged_cycle_pk = row_data["cycle_pk"]
            if merged_source_id is None and row_data["source_id"] is not None:
                merged_source_id = row_data["source_id"]
            if merged_exists is None and row_data["exists_at_record_time"] is not None:
                merged_exists = row_data["exists_at_record_time"]
            if merged_size is None and row_data["size_bytes"] is not None:
                merged_size = row_data["size_bytes"]
            if merged_created is None and row_data["created_epoch"] is not None:
                merged_created = row_data["created_epoch"]
            if merged_observed is None and row_data["observed_epoch"] is not None:
                merged_observed = row_data["observed_epoch"]
            if merged_retained is None and row_data["retained"] is not None:
                merged_retained = row_data["retained"]
            if not merged_details and row_data["details_json"]:
                merged_details = row_data["details_json"]
        conn.execute(
            """
            update artifact_refs
            set cycle_pk=?, source_id=?, exists_at_record_time=?, size_bytes=?,
                created_epoch=?, observed_epoch=?, retained=?, details_json=?
            where artifact_id=?
            """,
            (
                merged_cycle_pk,
                merged_source_id,
                merged_exists,
                merged_size,
                merged_created,
                merged_observed,
                merged_retained,
                merged_details,
                winner_id,
            ),
        )
        duplicate_ids = [int(row_data["artifact_id"]) for row_data in rows[1:]]
        placeholders = ",".join("?" for _ in duplicate_ids)
        conn.execute(f"delete from artifact_refs where artifact_id in ({placeholders})", duplicate_ids)
    return duplicate_groups


def ensure_artifact_ref_identity_indexes(conn: sqlite3.Connection) -> int:
    try:
        columns = {row["name"] for row in conn.execute("pragma table_info(artifact_refs)").fetchall()}
    except sqlite3.Error:
        return 0
    required = {
        "artifact_id",
        "repo_id",
        "artifact_kind",
        "path",
        "sha256",
        "observed_epoch",
    }
    if not required.issubset(columns):
        return 0
    duplicate_groups = dedupe_artifact_refs(conn)
    try:
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_artifact_refs_unique_identity_digest ON artifact_refs(repo_id, artifact_kind, path, sha256) WHERE sha256 IS NOT NULL"
        )
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_artifact_refs_unique_identity_missing_digest ON artifact_refs(repo_id, artifact_kind, path) WHERE sha256 IS NULL"
        )
    except sqlite3.Error:
        pass
    return duplicate_groups


def ensure_file_snapshot_mtime_ns_column(conn: sqlite3.Connection) -> None:
    try:
        columns = {row["name"] for row in conn.execute("pragma table_info(file_snapshots)").fetchall()}
    except sqlite3.Error:
        return
    if "mtime_ns" not in columns:
        try:
            conn.execute("alter table file_snapshots add column mtime_ns integer")
        except sqlite3.Error:
            pass


def ensure_worktree_snapshot_path_mtime_ns_column(conn: sqlite3.Connection) -> None:
    try:
        columns = {row["name"] for row in conn.execute("pragma table_info(worktree_snapshot_paths)").fetchall()}
    except sqlite3.Error:
        return
    if "mtime_ns" not in columns:
        try:
            conn.execute("alter table worktree_snapshot_paths add column mtime_ns integer")
        except sqlite3.Error:
            pass


def ensure_worktree_snapshot_path_identity_columns(conn: sqlite3.Connection) -> None:
    try:
        columns = {row["name"] for row in conn.execute("pragma table_info(worktree_snapshot_paths)").fetchall()}
    except sqlite3.Error:
        return
    for column, sql in (
        ("path_hmac", "alter table worktree_snapshot_paths add column path_hmac text"),
        ("path_class", "alter table worktree_snapshot_paths add column path_class text"),
        ("old_path_hmac", "alter table worktree_snapshot_paths add column old_path_hmac text"),
        ("old_path_class", "alter table worktree_snapshot_paths add column old_path_class text"),
    ):
        if column not in columns:
            try:
                conn.execute(sql)
            except sqlite3.Error:
                pass


def ensure_source_record_identity_columns(conn: sqlite3.Connection) -> None:
    try:
        columns = {row["name"] for row in conn.execute("pragma table_info(source_records)").fetchall()}
    except sqlite3.Error:
        return
    if "source_line" not in columns:
        try:
            conn.execute("alter table source_records add column source_line integer")
        except sqlite3.Error:
            pass
    if "raw_sha256" not in columns:
        try:
            conn.execute("alter table source_records add column raw_sha256 text")
        except sqlite3.Error:
            pass
    try:
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_source_records_identity ON source_records(repo_id, source_kind, coalesce(source_path, ''), coalesce(source_line, -1), coalesce(raw_sha256, ''))"
        )
    except sqlite3.Error:
        pass


def ensure_contributor_privacy_columns(conn: sqlite3.Connection) -> None:
    try:
        columns = {row["name"] for row in conn.execute("pragma table_info(contributors)").fetchall()}
    except sqlite3.Error:
        return
    if "identity_hash" not in columns:
        try:
            conn.execute("alter table contributors add column identity_hash text")
        except sqlite3.Error:
            pass
    if "pii_included" not in columns:
        try:
            conn.execute("alter table contributors add column pii_included integer not null default 0")
        except sqlite3.Error:
            pass
    try:
        conn.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS idx_contributors_identity_hash ON contributors(identity_hash) WHERE identity_hash IS NOT NULL"
        )
    except sqlite3.Error:
        pass


def ensure_git_commit_privacy_columns(conn: sqlite3.Connection) -> None:
    try:
        columns = {row["name"] for row in conn.execute("pragma table_info(git_commits)").fetchall()}
    except sqlite3.Error:
        return
    if "subject_hash" not in columns:
        try:
            conn.execute("alter table git_commits add column subject_hash text")
        except sqlite3.Error:
            pass
    if "subject_length" not in columns:
        try:
            conn.execute("alter table git_commits add column subject_length integer")
        except sqlite3.Error:
            pass
    if "subject_included" not in columns:
        try:
            conn.execute("alter table git_commits add column subject_included integer not null default 0")
        except sqlite3.Error:
            pass


def scrub_legacy_git_privacy_data(conn: sqlite3.Connection) -> None:
    ensure_contributor_privacy_columns(conn)
    ensure_git_commit_privacy_columns(conn)
    contributor_columns = set(table_columns(conn, "contributors"))
    if {"contributor_id", "name", "email", "identity_hash", "pii_included"}.issubset(contributor_columns):
        for row in conn.execute("select contributor_id, name, email, github_login, identity_hash, pii_included from contributors"):
            identity_hash = str(row["identity_hash"] or "")
            name = row["name"] if isinstance(row["name"], str) else ""
            email = row["email"] if isinstance(row["email"], str) else ""
            if not identity_hash:
                identity_hash = contributor_identity_hash(name, email)
            pii_included = 1 if parse_bool_int(str(row["pii_included"]) if row["pii_included"] is not None else None) == 1 else 0
            if pii_included == 1:
                conn.execute(
                    "update contributors set identity_hash=? where contributor_id=?",
                    (identity_hash or None, int(row["contributor_id"])),
                )
                continue
            conn.execute(
                """
                update contributors
                set identity_hash=?, name=NULL, email=NULL, github_login=NULL, pii_included=0
                where contributor_id=?
                """,
                (identity_hash or None, int(row["contributor_id"])),
            )
    commit_columns = set(table_columns(conn, "git_commits"))
    if {"commit_id", "subject", "subject_hash", "subject_length", "subject_included"}.issubset(commit_columns):
        for row in conn.execute("select commit_id, subject, subject_hash, subject_length, subject_included from git_commits"):
            summary = commit_subject_summary(
                row["subject"] if isinstance(row["subject"], str) else None,
                row["subject_hash"],
                row["subject_length"],
                row["subject_included"],
            )
            if summary["subject_included"] == 1:
                conn.execute(
                    "update git_commits set subject_hash=?, subject_length=?, subject_included=1 where commit_id=?",
                    (summary["subject_hash"], summary["subject_length"], int(row["commit_id"])),
                )
                continue
            conn.execute(
                """
                update git_commits
                set subject=NULL, subject_hash=?, subject_length=?, subject_included=0
                where commit_id=?
                """,
                (summary["subject_hash"], summary["subject_length"], int(row["commit_id"])),
            )
    for row in conn.execute(
        "select source_id, source_kind, parsed_json from source_records where source_kind='local_git' and parsed_json is not null"
    ):
        payload = sanitize_source_record_payload(dict(row))
        if payload.get("parsed_json") != row["parsed_json"]:
            conn.execute(
                "update source_records set parsed_json=? where source_id=?",
                (payload.get("parsed_json"), int(row["source_id"])),
            )


def init_schema(conn: sqlite3.Connection, root: Path | None = None, *, raw_storage_mode: str | None = None) -> None:
    now = epoch_now()
    with conn:
        for sql in CREATE_TABLE_SQL:
            conn.execute(sql)
        deduped_artifact_ref_groups = ensure_artifact_ref_identity_indexes(conn)
        deduped_git_change_groups = dedupe_git_file_changes(conn)
        ensure_file_snapshot_mtime_ns_column(conn)
        ensure_worktree_snapshot_path_mtime_ns_column(conn)
        ensure_worktree_snapshot_path_identity_columns(conn)
        ensure_source_record_identity_columns(conn)
        ensure_contributor_privacy_columns(conn)
        ensure_git_commit_privacy_columns(conn)
        for sql in CREATE_INDEX_SQL:
            conn.execute(sql)
        scrub_legacy_git_privacy_data(conn)
        conn.execute("PRAGMA user_version=1")
        conn.execute(
            "insert or replace into schema_meta(key, value) values (?, ?)",
            ("schema_version", str(SCHEMA_VERSION)),
        )
        conn.execute(
            "insert or ignore into schema_meta(key, value) values (?, ?)",
            ("created_epoch", str(now)),
        )
        conn.execute(
            "insert or replace into schema_meta(key, value) values (?, ?)",
            ("updated_epoch", str(now)),
        )
        conn.execute(
            """
            insert or ignore into schema_migrations(
              migration_id, from_version, to_version, applied_epoch, status, script_hash, details_json
            ) values (?, ?, ?, ?, ?, ?, ?)
            """,
            (1, 0, 1, now, "applied", sha256_text("\n".join(CREATE_TABLE_SQL + CREATE_INDEX_SQL)), "{}"),
        )
        if deduped_git_change_groups:
            conn.execute(
                "insert or replace into schema_meta(key, value) values (?, ?)",
                ("git_file_changes_deduped_groups", str(deduped_git_change_groups)),
            )
            conn.execute(
                "insert or replace into schema_meta(key, value) values (?, ?)",
                ("git_file_changes_deduped_epoch", str(now)),
            )
        if deduped_artifact_ref_groups:
            conn.execute(
                "insert or replace into schema_meta(key, value) values (?, ?)",
                ("artifact_refs_deduped_groups", str(deduped_artifact_ref_groups)),
            )
            conn.execute(
                "insert or replace into schema_meta(key, value) values (?, ?)",
                ("artifact_refs_deduped_epoch", str(now)),
            )
    install_pass_registry(conn, root or default_root(), raw_storage_mode=raw_storage_mode)


def ensure_schema(conn: sqlite3.Connection) -> None:
    try:
        version = conn.execute("select value from schema_meta where key='schema_version'").fetchone()
    except sqlite3.Error:
        fail("schema_meta is missing; run init", EXIT_SCHEMA_MISMATCH)
    if not version or str(version["value"]) != str(SCHEMA_VERSION):
        fail(f"schema mismatch: expected {SCHEMA_VERSION}", EXIT_SCHEMA_MISMATCH)
    user_version = conn.execute("PRAGMA user_version").fetchone()[0]
    if int(user_version) != SCHEMA_VERSION:
        fail(f"PRAGMA user_version mismatch: expected {SCHEMA_VERSION}, got {user_version}", EXIT_SCHEMA_MISMATCH)
    ensure_artifact_ref_identity_indexes(conn)
    ensure_file_snapshot_mtime_ns_column(conn)
    ensure_worktree_snapshot_path_mtime_ns_column(conn)
    ensure_worktree_snapshot_path_identity_columns(conn)
    ensure_source_record_identity_columns(conn)
    scrub_legacy_git_privacy_data(conn)


def sanitize_remote_url(raw: str) -> str:
    if not raw:
        return ""
    raw = raw.strip()
    return re.sub(r"(https?://)[^/@\s]+@", r"\1<redacted>@", raw)


def repo_git_info(root: Path) -> dict[str, str]:
    info = {
        "git_common_dir": git_common_dir_path(root),
        "head_sha": git_output(root, ["rev-parse", "--verify", "HEAD"], ""),
        "head_tree_sha": git_output(root, ["rev-parse", "HEAD^{tree}"], ""),
        "branch_name": git_output(root, ["branch", "--show-current"], ""),
        "remote_url": sanitize_remote_url(git_output(root, ["config", "--get", "remote.origin.url"], "")),
    }
    return info


def upsert_repo_alias(
    conn: sqlite3.Connection,
    repo_id: int,
    alias_kind: str,
    alias_value: str,
    now: int,
) -> None:
    if not alias_value:
        return
    existing_for_repo = conn.execute(
        "select repo_alias_id, alias_value from repo_aliases where repo_id=? and alias_kind=?",
        (repo_id, alias_kind),
    ).fetchone()
    if existing_for_repo:
        existing_alias_id = int(existing_for_repo["repo_alias_id"])
        existing_alias_value = str(existing_for_repo["alias_value"] or "")
        if existing_alias_value != alias_value:
            conflict = conn.execute(
                "select repo_alias_id, repo_id from repo_aliases where alias_kind=? and alias_value=?",
                (alias_kind, alias_value),
            ).fetchone()
            if conflict and int(conflict["repo_id"]) != repo_id:
                return
            conn.execute(
                "update repo_aliases set alias_value=?, last_seen_epoch=? where repo_alias_id=?",
                (alias_value, now, existing_alias_id),
            )
            return
        conn.execute(
            "update repo_aliases set last_seen_epoch=? where repo_alias_id=?",
            (now, existing_alias_id),
        )
        return
    conflict = conn.execute(
        "select repo_alias_id, repo_id from repo_aliases where alias_kind=? and alias_value=?",
        (alias_kind, alias_value),
    ).fetchone()
    if conflict and int(conflict["repo_id"]) != repo_id:
        return
    conn.execute(
        """
        insert into repo_aliases(repo_id, alias_kind, alias_value, first_seen_epoch, last_seen_epoch)
        values (?, ?, ?, ?, ?)
        """,
        (repo_id, alias_kind, alias_value, now, now),
    )


def ensure_repository(conn: sqlite3.Connection, root: Path) -> int:
    now = epoch_now()
    root = root.resolve()
    info = repo_git_info(root)
    common = info["git_common_dir"]
    context = repo_identity_context(root, info)
    repo_key_src = f"{root}|{common}|{info['remote_url']}"
    repo_key = sha256_text(repo_key_src)
    identity = sanitize_repository_payload(
        {
            "root_path": str(root),
            "first_seen_root_path": str(root),
            "current_root_path": str(root),
            "working_tree_path": str(root),
            "git_common_dir": common,
            "branch_name": info["branch_name"],
            "remote_url": info["remote_url"],
            "origin_url_hash": info["remote_url"],
        },
        context,
    )
    origin_hash = str(identity.get("origin_url_hash") or "")
    row = conn.execute("select repo_id from repositories where repo_key=?", (repo_key,)).fetchone()
    if row:
        repo_id = int(row["repo_id"])
        conn.execute(
            """
            update repositories
            set current_root_path=?, working_tree_path=?, git_common_dir=?, head_sha=?,
                head_tree_sha=?, branch_name=?, remote_url=?, origin_url_hash=?, last_seen_epoch=?
            where repo_id=?
            """,
            (
                identity["current_root_path"],
                identity["working_tree_path"],
                identity["git_common_dir"],
                info["head_sha"],
                info["head_tree_sha"],
                identity["branch_name"],
                identity["remote_url"],
                origin_hash,
                now,
                repo_id,
            ),
        )
    else:
        cur = conn.execute(
            """
            insert into repositories(
              repo_key, root_path, first_seen_root_path, current_root_path, working_tree_path,
              git_common_dir, head_sha, head_tree_sha, branch_name, remote_url, origin_url_hash,
              created_epoch, last_seen_epoch
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                repo_key,
                identity["root_path"],
                identity["first_seen_root_path"],
                identity["current_root_path"],
                identity["working_tree_path"],
                identity["git_common_dir"],
                info["head_sha"],
                info["head_tree_sha"],
                identity["branch_name"],
                identity["remote_url"],
                origin_hash,
                now,
                now,
            ),
        )
        repo_id = int(cur.lastrowid)
    for kind, value in [
        ("root_path", identity["root_path"]),
        ("repo_key", repo_key),
        ("git_common_dir", identity["git_common_dir"]),
        ("remote_url_hash", origin_hash),
    ]:
        if not value:
            continue
        upsert_repo_alias(conn, repo_id, kind, value, now)
    scrub_repo_identity_rows(conn, repo_id, context)
    scrub_source_record_rows(conn, root, repo_id)
    return repo_id


def lookup_repository_id(conn: sqlite3.Connection, root: Path) -> int | None:
    root = root.resolve()
    info = repo_git_info(root)
    repo_key = sha256_text(f"{root}|{info['git_common_dir']}|{info['remote_url']}")
    row = conn.execute("select repo_id from repositories where repo_key=?", (repo_key,)).fetchone()
    return int(row["repo_id"]) if row else None


def ensure_source_record(
    conn: sqlite3.Connection,
    root: Path,
    repo_id: int,
    source_kind: str,
    *,
    source_path: str = "",
    source_uri: str = "",
    source_epoch: int | None = None,
    raw_ref: str = "",
    raw_text: str | None = None,
    parsed: Any = None,
    parse_status: str = "parsed",
    fact_confidence: str = "observed",
    source_line: int | str | None = None,
    raw_sha256: str | None = None,
    raw_storage_mode: str | None = None,
) -> int:
    if source_kind not in SOURCE_KINDS:
        source_kind = "operator"
    now = epoch_now()
    stored_source_path = source_record_storage_path(root, source_kind, source_path)
    stored_source_uri = source_record_storage_uri(root, source_kind, source_uri)
    try:
        stored_source_line = int(source_line) if source_line is not None else None
    except (TypeError, ValueError):
        stored_source_line = None
    stored_raw_text = raw_text if effective_lattice_raw_storage(raw_storage_mode) == "full" else None
    stored_parsed = normalize_source_record_parsed(
        source_kind,
        raw_ref,
        parse_status,
        parsed,
        raw_storage_mode=raw_storage_mode,
    )
    parsed_payload_text = json_dumps(stored_parsed) if stored_parsed is not None else None
    if isinstance(raw_sha256, str) and raw_sha256.strip():
        computed_raw_sha256 = raw_sha256.strip()
    elif isinstance(stored_raw_text, str):
        computed_raw_sha256 = sha256_text(stored_raw_text)
    elif parsed_payload_text is not None:
        computed_raw_sha256 = sha256_text(parsed_payload_text)
    else:
        computed_raw_sha256 = None
    stored_raw_sha256 = computed_raw_sha256
    identity_path = stored_source_path or ""
    identity_line = stored_source_line if stored_source_line is not None else -1
    identity_sha = stored_raw_sha256 or ""
    row = conn.execute(
        """
        select source_id
        from source_records
        where repo_id=?
          and source_kind=?
          and coalesce(source_path, '') = ?
          and coalesce(source_line, -1) = ?
          and coalesce(raw_sha256, '') = ?
        order by imported_epoch desc, source_id desc
        limit 1
        """,
        (repo_id, source_kind, identity_path, identity_line, identity_sha),
    ).fetchone()
    if row:
        source_id = int(row["source_id"])
        conn.execute(
            """
            update source_records
            set source_path=?, source_uri=?, source_epoch=?, source_line=?, raw_ref=?, raw_text=coalesce(?, raw_text),
                parsed_json=coalesce(?, parsed_json), parse_status=?, fact_confidence=?, raw_sha256=?, imported_epoch=?
            where source_id=?
            """,
            (
                stored_source_path,
                stored_source_uri,
                source_epoch,
                stored_source_line,
                raw_ref or None,
                stored_raw_text,
                parsed_payload_text,
                parse_status,
                fact_confidence,
                stored_raw_sha256,
                now,
                source_id,
            ),
        )
        return source_id
    cur = conn.execute(
        """
        insert into source_records(
          repo_id, source_kind, source_path, source_uri, source_epoch, imported_epoch,
          source_line, raw_ref, raw_text, raw_sha256, parsed_json, parse_status, fact_confidence
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            repo_id,
            source_kind,
            stored_source_path or None,
            stored_source_uri or None,
            source_epoch,
            now,
            stored_source_line,
            raw_ref or None,
            stored_raw_text,
            stored_raw_sha256,
            json_dumps(stored_parsed) if stored_parsed is not None else None,
            parse_status,
            fact_confidence,
        ),
    )
    return int(cur.lastrowid)


def git_head_file_paths(root: Path) -> set[str]:
    raw = git_output(root, ["ls-tree", "-r", "--name-only", "HEAD"], default="", strip=False)
    if not raw:
        return set()
    paths: set[str] = set()
    for path in raw.splitlines():
        stored = stored_rel_path(path.strip())
        if stored:
            paths.add(stored)
    return paths


def sync_file_current_state_to_head(
    conn: sqlite3.Connection,
    root: Path,
    repo_id: int,
    source_id: int | None = None,
) -> None:
    head_paths = git_head_file_paths(root)
    if not head_paths:
        return
    now = epoch_now()
    for path in head_paths:
        row = conn.execute(
            """
            select file_id, current_path, current_state
            from files
            where repo_id=? and (current_path=? or canonical_path=?)
            """,
            (repo_id, path, path),
        ).fetchone()
        if row:
            file_id = int(row["file_id"])
            current_path = stored_rel_path(str(row["current_path"] or ""))
            current_state = str(row["current_state"] or "")
            target_state = "active" if current_state in {"deleted", "unknown"} else current_state
            if current_path != path:
                conn.execute(
                    "update files set current_path=?, current_state=?, last_seen_epoch=? where file_id=?",
                    (path, target_state, now, file_id),
                )
            elif target_state != current_state:
                conn.execute(
                    "update files set current_state=?, last_seen_epoch=? where file_id=?",
                    (target_state, now, file_id),
                )
            else:
                conn.execute("update files set last_seen_epoch=? where file_id=?", (now, file_id))
            conn.execute(
                """
                insert into file_paths(file_id, path, first_seen_epoch, last_seen_epoch, source_id)
                values (?, ?, ?, ?, ?)
                on conflict(file_id, path) do update set
                  last_seen_epoch=excluded.last_seen_epoch,
                  source_id=coalesce(excluded.source_id, file_paths.source_id)
                """,
                (file_id, path, now, now, source_id),
            )
        else:
            ensure_file(
                conn,
                repo_id,
                path,
                state="active",
                source_id=source_id,
            )
    for row in conn.execute(
        "select file_id, current_path, current_state from files where repo_id=?",
        (repo_id,),
    ):
        file_id = int(row["file_id"])
        current_path = stored_rel_path(str(row["current_path"] or ""))
        current_state = str(row["current_state"] or "")
        if current_path and current_path not in head_paths and current_state != "deleted":
            conn.execute(
                "update files set current_state='deleted', last_seen_epoch=? where file_id=?",
                (now, file_id),
            )


def ensure_file(
    conn: sqlite3.Connection,
    repo_id: int,
    path: str,
    *,
    canonical_path: str | None = None,
    state: str = "active",
    source_id: int | None = None,
    prefer_historical_match: bool = False,
) -> int:
    now = epoch_now()
    path = stored_rel_path(path)
    canonical = stored_rel_path(canonical_path or path)
    if not path:
        raise ValueError("empty path")
    row = None
    if not prefer_historical_match and canonical == path:
        row = conn.execute(
            """
            select file_id
            from files
            where repo_id=? and current_path=?
            order by case when canonical_path <> ? then 0 else 1 end, file_id
            limit 1
            """,
            (repo_id, path, path),
        ).fetchone()
    if not row:
        row = conn.execute(
            "select file_id from files where repo_id=? and canonical_path=?",
            (repo_id, canonical),
        ).fetchone()
    if not row:
        row = conn.execute(
            """
            select f.file_id
            from file_paths p
            join files f on f.file_id=p.file_id
            where f.repo_id=? and p.path=?
            order by f.last_seen_epoch desc, f.file_id
            limit 1
            """,
            (repo_id, path),
        ).fetchone()
    if not row and prefer_historical_match and canonical == path:
        row = conn.execute(
            """
            select file_id
            from files
            where repo_id=? and current_path=?
            order by case when canonical_path <> ? then 0 else 1 end, file_id
            limit 1
            """,
            (repo_id, path, path),
        ).fetchone()
    if row:
        file_id = int(row["file_id"])
        conn.execute(
            "update files set current_path=?, current_state=?, last_seen_epoch=? where file_id=?",
            (path, state, now, file_id),
        )
    else:
        cur = conn.execute(
            """
            insert into files(repo_id, canonical_path, first_seen_epoch, last_seen_epoch, current_path, current_state)
            values (?, ?, ?, ?, ?, ?)
            """,
            (repo_id, canonical, now, now, path, state),
        )
        file_id = int(cur.lastrowid)
    conn.execute(
        """
        insert into file_paths(file_id, path, first_seen_epoch, last_seen_epoch, source_id)
        values (?, ?, ?, ?, ?)
        on conflict(file_id, path) do update set
          last_seen_epoch=excluded.last_seen_epoch,
          source_id=coalesce(excluded.source_id, file_paths.source_id)
        """,
        (file_id, path, now, now, source_id),
    )
    return file_id


def ensure_file_historical_only(
    conn: sqlite3.Connection,
    repo_id: int,
    path: str,
    *,
    canonical_path: str | None = None,
    source_id: int | None = None,
) -> int:
    now = epoch_now()
    path = stored_rel_path(path)
    canonical = stored_rel_path(canonical_path or path)
    if not path:
        raise ValueError("empty path")
    # Never rely on current_path for historical imports: current snapshots may have
    # already created a different lineage for a path before full git history replay.
    # Match by canonical path first, then by historical file-path aliases.
    row = None
    if not row:
        row = conn.execute(
            "select file_id from files where repo_id=? and canonical_path=?",
            (repo_id, canonical),
        ).fetchone()
    if not row:
        row = conn.execute(
            """
            select f.file_id
            from file_paths p
            join files f on f.file_id=p.file_id
            where f.repo_id=? and p.path=?
            order by f.last_seen_epoch desc, f.file_id
            limit 1
            """,
            (repo_id, path),
        ).fetchone()
    if row:
        file_id = int(row["file_id"])
        conn.execute(
            "update files set last_seen_epoch=? where file_id=?",
            (now, file_id),
        )
    else:
        cur = conn.execute(
            """
            insert into files(repo_id, canonical_path, first_seen_epoch, last_seen_epoch, current_path, current_state)
            values (?, ?, ?, ?, ?, 'unknown')
            """,
            (repo_id, canonical, now, now, path),
        )
        file_id = int(cur.lastrowid)
    conn.execute(
        """
        insert into file_paths(file_id, path, first_seen_epoch, last_seen_epoch, source_id)
        values (?, ?, ?, ?, ?)
        on conflict(file_id, path) do update set
          last_seen_epoch=excluded.last_seen_epoch,
          source_id=coalesce(excluded.source_id, file_paths.source_id)
        """,
        (file_id, path, now, now, source_id),
    )
    return file_id


def merge_file_lineage(
    conn: sqlite3.Connection,
    source_file_id: int,
    target_file_id: int,
) -> int:
    if source_file_id == target_file_id:
        return target_file_id
    source = conn.execute(
        """
        select file_id, canonical_path, current_path, current_state, first_seen_epoch, last_seen_epoch
        from files
        where file_id=?
        """,
        (source_file_id,),
    ).fetchone()
    target = conn.execute(
        """
        select file_id, canonical_path, current_path, current_state, first_seen_epoch, last_seen_epoch
        from files
        where file_id=?
        """,
        (target_file_id,),
    ).fetchone()
    if not source or not target:
        return target_file_id

    now = epoch_now()
    merged_first_seen = min(
        value
        for value in (source["first_seen_epoch"], target["first_seen_epoch"])
        if value is not None
    )
    merged_last_seen = max(
        value
        for value in (source["last_seen_epoch"], target["last_seen_epoch"], now)
        if value is not None
    )
    merged_canonical = str(target["canonical_path"] or target["current_path"] or source["canonical_path"] or source["current_path"])
    merged_current_path = str(target["current_path"] or source["current_path"] or merged_canonical)
    merged_state = str(target["current_state"] or source["current_state"] or "unknown")
    if merged_state == "unknown" and source["current_state"]:
        merged_state = str(source["current_state"])

    conn.execute(
        """
        update files
        set canonical_path=?,
            first_seen_epoch=?,
            last_seen_epoch=?,
            current_path=?,
            current_state=?
        where file_id=?
        """,
        (
            merged_canonical,
            merged_first_seen,
            merged_last_seen,
            merged_current_path,
            merged_state,
            target_file_id,
        ),
    )
    conn.execute(
        """
        insert into file_paths(file_id, path, first_seen_epoch, last_seen_epoch, source_id)
        select ?, path, first_seen_epoch, last_seen_epoch, source_id
        from file_paths
        where file_id=?
        on conflict(file_id, path) do update set
          first_seen_epoch=case
            when file_paths.first_seen_epoch is null then excluded.first_seen_epoch
            when excluded.first_seen_epoch is null then file_paths.first_seen_epoch
            when excluded.first_seen_epoch < file_paths.first_seen_epoch then excluded.first_seen_epoch
            else file_paths.first_seen_epoch
          end,
          last_seen_epoch=case
            when file_paths.last_seen_epoch is null then excluded.last_seen_epoch
            when excluded.last_seen_epoch is null then file_paths.last_seen_epoch
            when excluded.last_seen_epoch > file_paths.last_seen_epoch then excluded.last_seen_epoch
            else file_paths.last_seen_epoch
          end,
          source_id=coalesce(file_paths.source_id, excluded.source_id)
        """,
        (target_file_id, source_file_id),
    )
    for table, column in (
        ("cycles", "selected_file_id"),
        ("selection_runs", "selected_file_id"),
        ("selection_candidates", "file_id"),
        ("file_snapshots", "file_id"),
        ("file_events", "file_id"),
        ("git_file_changes", "file_id"),
        ("tool_failures", "file_id"),
        ("regression_events", "file_id"),
        ("regression_causes", "cause_file_id"),
        ("change_log_file_refs", "file_id"),
        ("extension_facts", "file_id"),
        ("operator_annotations", "file_id"),
        ("file_pass_runs", "file_id"),
        ("file_pass_rollups", "file_id"),
        ("file_fragility_rollups", "file_id"),
        ("file_git_churn_rollups", "file_id"),
        ("file_selection_rollups", "file_id"),
        ("file_failure_rollups", "file_id"),
    ):
        conn.execute(
            f"update {table} set {column}=? where {column}=?",
            (target_file_id, source_file_id),
        )
    conn.execute("delete from file_paths where file_id=?", (source_file_id,))
    try:
        conn.execute("delete from files where file_id=?", (source_file_id,))
    except sqlite3.IntegrityError:
        hidden_path = f"__merged__/file-{source_file_id}"
        conn.execute(
            """
            update files
            set canonical_path=?,
                current_path=?,
                current_state='merged',
                last_seen_epoch=?
            where file_id=?
            """,
            (hidden_path, hidden_path, now, source_file_id),
        )
    return target_file_id


def file_id_for_path(conn: sqlite3.Connection, repo_id: int, path: str) -> int | None:
    path = stored_rel_path(external_rel_path(path))
    if not path:
        return None
    row = conn.execute(
        """
        select file_id
        from files
        where repo_id=? and current_path=?
        order by case when canonical_path <> ? then 0 else 1 end, file_id
        limit 1
        """,
        (repo_id, path, path),
    ).fetchone()
    if row:
        return int(row["file_id"])
    row = conn.execute(
        """
        select f.file_id
        from file_paths p
        join files f on f.file_id=p.file_id
        where f.repo_id=? and p.path=?
        order by case when f.current_path=? then 0 else 1 end, f.last_seen_epoch desc, f.file_id
        limit 1
        """,
        (repo_id, path, path),
    ).fetchone()
    return int(row["file_id"]) if row else None


def normalize_rel_path(path: str) -> str:
    path = path.strip()
    if not path:
        return ""
    if re.match(r"^[A-Za-z]:[\\/]", path):
        return ""
    path = path.replace("\\", "/")
    path = re.sub(r"^\./+", "", path)
    parts: list[str] = []
    for part in path.split("/"):
        if not part or part == ".":
            continue
        if part == "..":
            return ""
        parts.append(part)
    return "/".join(parts)


def normalize_change_note_ref(path: str) -> str:
    path = path.strip()
    if not path:
        return ""
    if any(ch in path for ch in "\x00\r\n\t"):
        return ""
    if any(ch in path for ch in ["`", "'", '"']):
        return ""
    if path.startswith(("/", "\\")):
        return ""
    if path.startswith("~" + "/") or path.startswith("~" + "\\"):
        return ""
    if re.search(r"^[A-Za-z][A-Za-z0-9+\-.]*://", path):
        return ""
    if re.match(r"^[A-Za-z]:[\\/]", path):
        return ""
    if path.startswith(("../", "..\\")) or path == "..":
        return ""
    canonical = path.replace("\\", "/")
    if canonical.startswith("./") or canonical.startswith("~") or "//" in canonical:
        return ""
    normalized = normalize_rel_path(canonical)
    if not normalized or normalized != canonical:
        return ""
    if "//" in normalized:
        return ""
    if re.search(r"(?:^|/)\.(?:/|$)", normalized):
        return ""
    return normalized


HOST_LIKE_PATH_SEGMENT_PATTERN = re.compile(
    r"^(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?::\d+)?$",
    re.IGNORECASE,
)


def is_unsafe_change_note_ref(path: str) -> bool:
    if not path:
        return False
    parsed = urlsplit(path)
    if parsed.scheme:
        return True
    if path.startswith("//"):
        return True
    if "/" not in path:
        return False
    first_segment = path.split("/", 1)[0]
    return bool(HOST_LIKE_PATH_SEGMENT_PATTERN.fullmatch(first_segment))


def normalize_repo_file_identity_ref(root: Path, path: str) -> str:
    # Change-note imports may mention URLs and runtime artifacts in prose, but
    # only repo-local source paths should become durable file identities.
    normalized = normalize_change_note_ref(path)
    if not normalized:
        return ""
    if is_unsafe_change_note_ref(normalized):
        return ""
    if normalized == "Upkeeper.log" or normalized.startswith((".git/", "runtime/")):
        return ""
    try:
        resolved = (root / normalized).resolve(strict=False)
        resolved.relative_to(root)
    except (OSError, RuntimeError, ValueError):
        return ""
    return normalized


def tool_failure_marker_identity(
    root: Path,
    marker_path: Path,
    payload: Any,
) -> tuple[str, str, str]:
    raw_marker_id = marker_path.stem
    if not isinstance(payload, dict):
        return "", "", raw_marker_id
    if isinstance(payload.get("marker_id"), str) and payload["marker_id"].strip():
        raw_marker_id = payload["marker_id"].strip()
    raw_target = payload.get("target_path")
    if not isinstance(raw_target, str):
        return "", "", raw_marker_id
    target_path = repo_relative_target_path(root, raw_target)
    if not target_path:
        return "", "", raw_marker_id
    # Equivalent path spellings must collapse to one marker identity in Lattice.
    digest = hashlib.sha1(target_path.encode("utf-8", "surrogateescape")).hexdigest()
    return target_path, digest[:TOOL_FAILURE_MARKER_ID_HEX_LENGTH], raw_marker_id


def ensure_cycle(
    conn: sqlite3.Connection,
    repo_id: int,
    cycle_id: str,
    run_hash: str,
    *,
    source_id: int | None = None,
    start_epoch: int | None = None,
    **fields: Any,
) -> int:
    now = epoch_now()
    start_epoch = start_epoch or now
    row = conn.execute(
        "select cycle_pk from cycles where repo_id=? and cycle_id=? and run_hash=?",
        (repo_id, cycle_id, run_hash),
    ).fetchone()
    if row:
        cycle_pk = int(row["cycle_pk"])
        assignments = []
        values: list[Any] = []
        for key, value in fields.items():
            if key not in table_columns(conn, "cycles"):
                continue
            if not has_meaningful_value(value):
                continue
            assignments.append(f"{key}=?")
            values.append(value)
        if source_id is not None:
            assignments.append("source_id=coalesce(source_id, ?)")
            values.append(source_id)
        if assignments:
            values.append(cycle_pk)
            conn.execute(f"update cycles set {', '.join(assignments)} where cycle_pk=?", values)
        return cycle_pk
    columns = ["repo_id", "cycle_id", "run_hash", "start_epoch", "source_id"]
    values = [repo_id, cycle_id, run_hash, start_epoch, source_id]
    for key, value in fields.items():
        if key in table_columns(conn, "cycles") and key not in columns and has_meaningful_value(value):
            columns.append(key)
            values.append(value)
    placeholders = ",".join("?" for _ in columns)
    cur = conn.execute(
        f"insert into cycles({', '.join(columns)}) values ({placeholders})",
        values,
    )
    return int(cur.lastrowid)


def ensure_pass(conn: sqlite3.Connection, pass_code: str) -> int:
    pass_code = normalize_pass_code(pass_code)
    item = next((p for p in PASS_REGISTRY if p["pass_code"].upper() == pass_code.upper()), None)
    title = item["title"] if item else None
    prompt_source_path = item["prompt_source_path"] if item else None
    introduced_version = item["introduced_version"] if item else None
    active = 1 if (item is None or item.get("active", True)) else 0
    conn.execute(
        """
        insert into review_passes(pass_code, title, prompt_source_path, introduced_version, active)
        values (?, ?, ?, ?, ?)
        on conflict(pass_code) do update set
          title=coalesce(excluded.title, review_passes.title),
          prompt_source_path=coalesce(excluded.prompt_source_path, review_passes.prompt_source_path),
          introduced_version=coalesce(excluded.introduced_version, review_passes.introduced_version),
          active=excluded.active
        """,
        (pass_code, title, prompt_source_path, introduced_version, active),
    )
    row = conn.execute("select pass_id from review_passes where pass_code=?", (pass_code,)).fetchone()
    return int(row["pass_id"])


def install_pass_registry(conn: sqlite3.Connection, root: Path, *, raw_storage_mode: str | None = None) -> None:
    now = epoch_now()
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(
            conn,
            root,
            repo_id,
            "wrapper_observed",
            raw_ref="pass_registry",
            parsed={"passes": PASS_REGISTRY},
            parse_status="registry",
            raw_storage_mode=raw_storage_mode,
        )
        conn.execute(
            """
            insert into extension_namespaces(namespace, owner, description, introduced_epoch, active, source_id)
            values (?, ?, ?, ?, 1, ?)
            on conflict(namespace) do update set active=1, source_id=excluded.source_id
            """,
            (
                "upkeeper.review_pass_registry",
                "Upkeeper",
                "Deterministic review pass registry extension facts",
                now,
                source_id,
            ),
        )
        for key, value_type in [
            ("default_in_repertoire", "integer"),
            ("module_prompt", "integer"),
            ("aliases", "json"),
            ("applicability_hint", "text"),
            ("schedule_hint", "text"),
        ]:
            conn.execute(
                """
                insert into extension_fact_types(namespace, key, subject_type, value_type, description)
                values (?, ?, ?, ?, ?)
                on conflict(namespace, key, subject_type) do update set
                  value_type=excluded.value_type,
                  active=1
                """,
                ("upkeeper.review_pass_registry", key, "review_pass", value_type, f"Review pass registry {key}"),
            )
        for item in PASS_REGISTRY:
            pass_id = ensure_pass(conn, item["pass_code"])
            facts = {
                "default_in_repertoire": ("integer", int(bool(item["default_in_repertoire"]))),
                "module_prompt": ("integer", int(bool(item["module_prompt"]))),
                "aliases": ("json", item["aliases"]),
                "applicability_hint": ("text", item["applicability_hint"]),
                "schedule_hint": ("text", item["schedule_hint"]),
            }
            for key, (value_type, value) in facts.items():
                value_text = value if value_type == "text" else None
                value_integer = value if value_type == "integer" else None
                value_json = json_dumps(value) if value_type == "json" else None
                conn.execute(
                    """
                    insert or replace into extension_facts(
                      namespace, key, subject_type, subject_pk, value_type, value_text,
                      value_integer, value_json, confidence, source_id, created_epoch
                    ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        "upkeeper.review_pass_registry",
                        key,
                        "review_pass",
                        pass_id,
                        value_type,
                        value_text,
                        value_integer,
                        value_json,
                        "registry",
                        source_id,
                        now,
                    ),
                )


def normalize_pass_code(raw: str) -> str:
    raw = raw.strip()
    if not re.fullmatch(r"P[0-9A-Za-z_.-]+", raw):
        fail(f"invalid pass code: {raw}", EXIT_USAGE)
    return raw.upper() if re.fullmatch(r"P[0-9]+", raw, re.I) else raw


def parse_bool_int(raw: str | None) -> int | None:
    if raw is None or raw == "":
        return None
    raw = str(raw).strip().lower()
    if raw in {"1", "true", "yes", "on"}:
        return 1
    if raw in {"0", "false", "no", "off"}:
        return 0
    return None


def parse_pass_result_bool(raw: Any, field: str) -> int | None:
    if not has_meaningful_value(raw):
        return None
    parsed = parse_bool_int(str(raw))
    if parsed is None:
        raise ValueError(f"{field} must be one of: 0,1,yes,no,true,false,on,off")
    return parsed


def validate_pass_result_state(*, applicable: int | None, outcome: str) -> str | None:
    if outcome == "planned":
        if applicable is not None:
            return "planned outcome requires applicable to be unset"
        return None
    if outcome == "unknown":
        if applicable == 0:
            return "applicable=0 requires outcome=not_applicable"
        return None
    if outcome == "not_applicable":
        if applicable != 0:
            return "not_applicable requires applicable=0"
        return None
    if applicable == 0:
        return "applicable=0 requires outcome=not_applicable"
    if outcome in PASS_OUTCOMES_REQUIRING_APPLICABLE_TRUE:
        if applicable != 1:
            return f"{outcome} requires applicable=1"
    elif applicable is None:
        return f"outcome={outcome} requires applicable=1"
    return None


def require_jsonl_int(raw: Any, field: str) -> int:
    if not isinstance(raw, int) or isinstance(raw, bool):
        raise TypeError(f"{field} must be an integer, got {type(raw).__name__}")
    return raw


def parse_bool_flag(raw: str | None) -> bool:
    if raw is None or raw is True:
        return True
    parsed = parse_bool_int(str(raw))
    if parsed is None:
        raise argparse.ArgumentTypeError(f"expected boolean value, got {raw!r}")
    return bool(parsed)


def has_meaningful_value(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return value.strip() != ""
    return True


def parse_optional_dirty_paths(raw: Any) -> int | None:
    if not has_meaningful_value(raw):
        return None
    text = str(raw).strip()
    if not text.isdigit():
        return None
    return 1 if int(text) > 0 else 0


def record_file_event(
    conn: sqlite3.Connection,
    repo_id: int,
    event_kind: str,
    *,
    file_id: int | None = None,
    cycle_pk: int | None = None,
    source_id: int | None = None,
    path: str | None = None,
    confidence: str = "observed",
    details: Any = None,
    event_epoch: int | None = None,
) -> None:
    stored_path = stored_rel_path(path) if path else None
    conn.execute(
        """
        insert into file_events(repo_id, file_id, cycle_pk, source_id, event_kind, event_epoch, path, confidence, details_json)
        values (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            repo_id,
            file_id,
            cycle_pk,
            source_id,
            event_kind,
            event_epoch or epoch_now(),
            stored_path,
            confidence,
            json_dumps(details) if details is not None else None,
        ),
    )


def live_file_metadata(root: Path, rel_path: str) -> dict[str, Any]:
    rel_path = operational_rel_path(rel_path)
    meta: dict[str, Any] = {"path": stored_rel_path(rel_path)}
    if has_surrogate_codepoint(rel_path):
        meta["source_safety_reason"] = "invalid_path_encoding"
        meta["git_status"] = "unreadable"
        meta["worktree_hash"] = "unavailable"
        meta["head_blob"] = "unavailable"
        meta["content_state"] = "unreadable"
        meta["ignored"] = 0
        meta["test_path"] = 1 if is_test_path(rel_path) else 0
        meta["generated"] = 0
        meta["mtime_epoch"] = None
        meta["mtime_ns"] = None
        meta["size_bytes"] = None
        meta["executable"] = None
        meta["is_regular"] = 0
        return meta
    st, safety_reason = source_safe_file_stat(root, rel_path)
    if st is not None:
        meta["mtime_epoch"] = int(st.st_mtime)
        meta["mtime_ns"] = int(st.st_mtime_ns)
        meta["size_bytes"] = int(st.st_size)
        meta["executable"] = 1 if st.st_mode & 0o111 else 0
        meta["is_regular"] = 1 if stat.S_ISREG(st.st_mode) else 0
    else:
        meta.update(
            {
                "mtime_epoch": None,
                "mtime_ns": None,
                "size_bytes": None,
                "executable": None,
                "is_regular": 0,
            }
        )
    meta["source_safety_reason"] = safety_reason
    if safety_reason == "symlink":
        meta["git_status"] = "symlink"
        meta["worktree_hash"] = "unavailable"
        meta["head_blob"] = "none"
        meta["content_state"] = "symlink"
        meta["ignored"] = 1 if git_path_ignored(root, root / rel_path) else 0
        meta["test_path"] = 1 if is_test_path(rel_path) else 0
        meta["generated"] = 0
        return meta
    status = git_porcelain_status_for_path(root, rel_path)
    meta["git_status"] = stored_git_status_code(status) if status else "clean"
    raw_worktree_hash = git_output(root, ["hash-object", "--", rel_path], "missing") if st is not None else "unavailable"
    raw_head_blob = git_output(root, ["rev-parse", f"HEAD:{rel_path}"], "none")
    if raw_head_blob == "none":
        meta["content_state"] = "untracked"
    elif raw_head_blob == raw_worktree_hash:
        meta["content_state"] = "matches_head"
    else:
        meta["content_state"] = "differs_from_head"
    meta["worktree_hash"] = content_value_hmac(root, raw_worktree_hash)
    meta["head_blob"] = content_value_hmac(root, raw_head_blob)
    meta["ignored"] = 1 if git_path_ignored(root, root / rel_path) else 0
    meta["test_path"] = 1 if is_test_path(rel_path) else 0
    meta["generated"] = 0
    return meta


def insert_file_snapshot(
    conn: sqlite3.Connection,
    root: Path,
    repo_id: int,
    rel_path: str,
    *,
    file_id: int | None = None,
    source_id: int | None = None,
    observed_epoch: int | None = None,
) -> int:
    meta = live_file_metadata(root, rel_path)
    if file_id is None and rel_path:
        file_id = ensure_file(conn, repo_id, rel_path, source_id=source_id)
    if not file_id:
        raise ValueError("file_id required for snapshot")
    stored_path = stored_rel_path(rel_path)
    cur = conn.execute(
        """
        insert into file_snapshots(
          file_id, repo_id, path, observed_epoch, source_id, git_status, content_state,
          head_blob, worktree_hash, mtime_epoch, mtime_ns, size_bytes, executable, ignored, generated, test_path
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            file_id,
            repo_id,
            stored_path,
            observed_epoch or epoch_now(),
            source_id,
            meta.get("git_status"),
            meta.get("content_state"),
            meta.get("head_blob"),
            meta.get("worktree_hash"),
            meta.get("mtime_epoch"),
            meta.get("mtime_ns"),
            meta.get("size_bytes"),
            meta.get("executable"),
            meta.get("ignored"),
            meta.get("generated"),
            meta.get("test_path"),
        ),
    )
    return int(cur.lastrowid)


def parse_key_value_file(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path or not path.exists():
        return data
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


def parse_key_value_text(text: str) -> dict[str, str]:
    data: dict[str, str] = {}
    for line in text.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            data[key.strip()] = value.strip()
    return data


def selector_priority_gate(selection_mode: str) -> str:
    mapping = {
        "explicit_target": "explicit_target",
        "startup_anomaly_gate": "startup_anomaly",
        "failure_queue": "failure_queue",
        "stale_self_review": "stale_self_review",
        "automatic_rotation": "oldest_mtime",
    }
    return mapping.get(selection_mode, "lattice_mode" if selection_mode.startswith("lattice") else "none")


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if not path or not path.exists():
        return rows
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            try:
                obj = json.loads(raw)
            except json.JSONDecodeError:
                rows.append({"path": "", "candidate_state": "excluded", "exclusion_reason": "malformed_candidate_json"})
                continue
            if isinstance(obj, dict):
                rows.append(obj)
    return rows


def key_requires_path_redaction(key: str | None) -> bool:
    if not key:
        return False
    normalized = key
    if "-" in normalized or " " in normalized or any(char.isupper() for char in normalized):
        normalized = REDACTION_KEY_SEPARATORS.sub("_", REDACTION_KEY_NORMALIZER.sub("_", normalized))
    normalized = REDACTION_KEY_UNDERSCORE_COLLAPSE.sub("_", normalized).strip("_. ").lower()
    if not normalized:
        return False
    if normalized in REDACTABLE_PATH_KEYS or normalized == "selected_file":
        return True
    if normalized.endswith(("_path", "_paths", "_uri", "_uris")):
        return True
    tokens = set(normalized.split("_"))
    if "path" in tokens or "uri" in tokens:
        return True
    if "selected" in tokens and ("path" in tokens or "file" in tokens):
        return True
    return False


def looks_like_json_container_string(value: str) -> bool:
    stripped = value.strip()
    return len(stripped) >= 2 and stripped[0] in "{[" and stripped[-1] in "}]"


def redact_inline_assignment_string(
    raw: str,
    *,
    redact_paths: bool,
    redact_contributors: bool,
) -> str:
    if not raw or (not redact_paths and not redact_contributors):
        return raw

    def _replace(match: re.Match[str]) -> str:
        key = match.group("key")
        value = match.group("value")
        replacement = value
        if redact_paths and key_requires_path_redaction(key):
            replacement = REDACTED_PATH_PREFIX + sha256_text(value)
        elif redact_contributors and key in CONTRIBUTOR_REDACT_KEYS:
            replacement = "<redacted>"
        else:
            return match.group(0)
        return f"{match.group('prefix')}{key}={match.group('quote')}{replacement}{match.group('quote')}"

    return INLINE_ASSIGNMENT_PATTERN.sub(_replace, raw)


def has_redacted_inline_assignment_string(raw: str) -> bool:
    for match in INLINE_ASSIGNMENT_PATTERN.finditer(raw):
        if key_requires_path_redaction(match.group("key")) and match.group("value").startswith(REDACTED_PATH_PREFIX):
            return True
    return False


def has_redacted_path_token(payload: Any, current_key: str | None = None) -> bool:
    if isinstance(payload, dict):
        for key, value in payload.items():
            if has_redacted_path_token(value, key):
                return True
    elif isinstance(payload, list):
        for value in payload:
            if has_redacted_path_token(value, current_key):
                return True
    elif isinstance(payload, str):
        if key_requires_path_redaction(current_key) and payload.startswith(REDACTED_PATH_PREFIX):
            return True
        if looks_like_json_container_string(payload):
            try:
                parsed = json.loads(payload)
            except (TypeError, json.JSONDecodeError):
                return has_redacted_inline_assignment_string(payload)
            return has_redacted_path_token(parsed, current_key)
        return has_redacted_inline_assignment_string(payload)
    return False


def is_test_path(path: str) -> bool:
    parts = path.split("/")
    name = parts[-1]
    return any(part in TEST_DIRS for part in parts) or name.startswith("test_") or name.endswith("_test.py")


def live_candidate_paths(root: Path, candidate_scope: str = "eligible", upkeeper_ignore_file: str | None = None) -> list[dict[str, Any]]:
    upkeeperignore_patterns = load_upkeeperignore_patterns(root, upkeeper_ignore_file)
    inside_git = inside_git_repo(root)
    if inside_git:
        if candidate_scope == "current-tracked":
            raw = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"])
        else:
            raw = subprocess.check_output(["git", "-C", str(root), "ls-files", "-co", "--exclude-standard", "-z"])
        paths = [p for p in decode_git_output(raw).split("\0") if p]
    else:
        paths = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [name for name in dirnames if name not in {".git", "runtime"}]
            for filename in filenames:
                rel = repo_rel_path(root, Path(dirpath) / filename)
                if rel:
                    paths.append(rel)
    git_ignored = git_ignored_paths(root, paths) if inside_git else set()
    rows = []
    for rel in paths:
        reason = ""
        state = "eligible"
        p = root / rel
        if rel == "Upkeeper.log":
            reason = "excluded_exact"
        elif rel.startswith(".git/") or rel.startswith("runtime/"):
            reason = "excluded_prefix"
        elif upkeeper_path_ignored(rel, upkeeperignore_patterns):
            reason = "upkeeperignore"
        elif rel in git_ignored:
            reason = "gitignore"
        else:
            st, reason = source_safe_file_stat(root, rel)
            if not reason and st is not None:
                if candidate_scope == "current-tracked":
                    _, reason = source_safe_file_stat(root, rel, require_text=True)
                else:
                    if is_test_path(rel):
                        reason = "test_path"
                    name = p.name
                    ext = p.suffix.lower()
                    candidate = name in BUILD_NAMES or ext in SCRIPT_EXTS
                    if not candidate and st.st_mode & 0o111:
                        _, text_reason = source_safe_file_stat(root, rel, require_text=True)
                        candidate = not text_reason
                        if text_reason:
                            reason = "executable_not_text"
                    if candidate and not reason:
                        _, reason = source_safe_file_stat(root, rel, require_text=True)
                    if not candidate and not reason:
                        reason = "unsupported_extension"
        if reason:
            state = "excluded"
        meta = live_file_metadata(root, rel)
        rows.append(
            {
                "path": stored_rel_path(rel),
                "candidate_state": state,
                "exclusion_reason": reason,
                "mtime_epoch": meta.get("mtime_epoch"),
                "git_status": meta.get("git_status"),
                "content_state": meta.get("content_state"),
                "head_blob": meta.get("head_blob"),
                "worktree_hash": meta.get("worktree_hash"),
            }
        )
    return rows


def current_scope_paths(conn: sqlite3.Connection, root: Path, repo_id: int, scope: str) -> list[str]:
    if scope == "current-eligible":
        return sorted(row["path"] for row in live_candidate_paths(root) if row["candidate_state"] == "eligible")
    if scope == "current-tracked":
        return sorted(
            row["path"]
            for row in live_candidate_paths(root, candidate_scope="current-tracked")
            if row["candidate_state"] == "eligible"
        )
    if scope == "deleted":
        return [
            str(row["current_path"])
            for row in conn.execute(
                "select current_path from files where repo_id=? and current_state='deleted' order by current_path",
                (repo_id,),
            )
        ]
    if scope == "selected-history":
        return [
            str(row["selected_path"])
            for row in conn.execute(
                "select distinct selected_path from cycles where repo_id=? and selected_path is not null order by selected_path",
                (repo_id,),
            )
        ]
    if scope == "all-known":
        return [
            str(row["current_path"])
            for row in conn.execute("select current_path from files where repo_id=? order by current_path", (repo_id,))
        ]
    return [
        str(row["current_path"])
        for row in conn.execute(
            "select current_path from files where repo_id=? and current_state in ('active','resurrected','renamed','unknown') order by current_path",
            (repo_id,),
        )
    ]


def format_rows(rows: list[dict[str, Any]], fmt: str) -> None:
    try:
        if fmt == "json":
            print_json(rows)
        elif fmt == "jsonl":
            for row in rows:
                print(json_dumps(row))
        elif fmt == "tsv":
            if not rows:
                return
            keys = list(rows[0].keys())
            print("\t".join(keys))
            for row in rows:
                print("\t".join("" if row.get(k) is None else safe_output_text(str(row.get(k))) for k in keys))
        else:
            if not rows:
                return
            keys = list(rows[0].keys())
            widths = {key: max(len(key), *(len(safe_output_text(str(row.get(key, "")))) for row in rows)) for key in keys}
            print("  ".join(key.ljust(widths[key]) for key in keys))
            for row in rows:
                print(
                    "  ".join(
                        safe_output_text(str(row.get(key, "") if row.get(key) is not None else "")).ljust(widths[key])
                        for key in keys
                    )
                )
    except BrokenPipeError:
        redirect_stdout_to_devnull()
        raise SystemExit(EXIT_SUCCESS)


def command_init(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    db_path = normalize_db_path(args.db, root)
    journal_mode = args.journal_mode
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    conn = connect_checked(
        root,
        db_path,
        journal_mode,
        allow_unsafe_db=args.allow_unsafe_db,
        create_parent=True,
        create_if_missing=True,
    )
    try:
        init_schema(conn, root, raw_storage_mode=raw_storage_mode)
        chmod_private(db_path)
    finally:
        conn.close()
    print_json({"status": "ok", "schema_version": SCHEMA_VERSION, "db_path": str(db_path)})
    return EXIT_SUCCESS


def probe_raw_storage_enforcement(conn: sqlite3.Connection, root: Path, repo_id: int) -> dict[str, dict[str, dict[str, bool]]]:
    checks: dict[str, dict[str, dict[str, bool]]] = {}
    safe_log_payload = {
        "timestamp": "2026-05-13T00:00:00-0700",
        "level": "INFO",
        "event": "cycle.start",
        "cycle": "probe",
        "run_hash": "probe",
        "execution_origin": "primary",
        "dry_run": "1",
    }
    replayed_quota_payload = {
        "timestamp": "2026-05-13T00:00:05-0700",
        "level": "WARN",
        "event": "quota.current",
        "cycle": "probe",
        "run_hash": "probe",
        "execution_origin": "primary",
        "dry_run": "0",
        "source": "/home/joe/.codex/sessions/2026/05/session.jsonl",
        "limit_id": "plan-123",
        "limit_name": "Example Plan",
        "plan_type": "paid",
        "snapshot_model_hint": "gpt-5.5",
        "primary_used": "91%",
        "primary_reset": "2026-05-13 01:00:00 -0700",
    }
    replayed_quota_raw_line = render_upkeeper_log_line(replayed_quota_payload)
    sanitized_quota_raw_line = sanitize_upkeeper_log_raw_text(root, replayed_quota_raw_line, replayed_quota_payload) or ""
    unsafe_selection_payload = {"selection": {"path": "secret.txt"}, "candidate_count": 1}
    imported_source_payload = {
        "source_kind": "wrapper_observed",
        "raw_ref": "preselect",
        "raw_text": '{"path":"secret.txt"}',
        "parsed_json": json_dumps(unsafe_selection_payload),
        "parse_status": "parsed",
        "fact_confidence": "observed",
    }
    imported_quota_source_payload = {
        "source_kind": "upkeeper_log",
        "source_path": "/home/joe/.codex/sessions/2026/05/session.jsonl",
        "source_uri": "file:///home/joe/.codex/sessions/2026/05/session.jsonl",
        "raw_ref": "quota.current",
        "raw_text": replayed_quota_raw_line,
        "parsed_json": json_dumps(replayed_quota_payload),
        "parse_status": "parsed",
        "fact_confidence": "observed",
    }
    for mode in ("none", "minimal", "limited", "full"):
        conn.execute(f"SAVEPOINT raw_storage_{mode}")
        try:
            safe_id = ensure_source_record(
                conn,
                root,
                repo_id,
                "upkeeper_log",
                raw_ref="cycle.start",
                raw_text="sensitive raw log line",
                parsed=safe_log_payload,
                raw_storage_mode=mode,
            )
            unsafe_id = ensure_source_record(
                conn,
                root,
                repo_id,
                "wrapper_observed",
                raw_ref="preselect",
                raw_text='{"path":"secret.txt"}',
                parsed=unsafe_selection_payload,
                raw_storage_mode=mode,
            )
            replayed_id = ensure_source_record(
                conn,
                root,
                repo_id,
                "upkeeper_log",
                source_path="/home/joe/.codex/sessions/2026/05/session.jsonl",
                source_uri="file:///home/joe/.codex/sessions/2026/05/session.jsonl",
                raw_ref="quota.current",
                parsed=replayed_quota_payload,
                raw_storage_mode=mode,
            )
            rejected_id = ensure_source_record(
                conn,
                root,
                repo_id,
                "transcript",
                raw_ref="pass_result_rejected:1",
                raw_text="UPKEEPER_PASS_RESULT: pass=P2 file=wrong.txt unexpected=1",
                parsed={
                    "line_number": 1,
                    "pass": "P2",
                    "path_hmac": pass_result_path_hmac(root, "wrong.txt"),
                    "selected_path_hmac": pass_result_path_hmac(root, "tools/upkeeper_lattice.py"),
                    "rejection_kind": "unexpected_key",
                    "reason": "unexpected_key:unexpected",
                },
                parse_status="rejected",
                fact_confidence="rejected",
                raw_storage_mode=mode,
            )
            imported_source_record = sanitize_imported_source_record_row(
                imported_source_payload,
                root=root,
                redact_raw=False,
                raw_storage_mode=mode,
            )
            imported_quota_source_record = sanitize_imported_source_record_row(
                imported_quota_source_payload,
                root=root,
                redact_raw=False,
                raw_storage_mode=mode,
            )
            safe_row = conn.execute(
                "select raw_text, parsed_json from source_records where source_id=?",
                (safe_id,),
            ).fetchone()
            unsafe_row = conn.execute(
                "select raw_text, parsed_json from source_records where source_id=?",
                (unsafe_id,),
            ).fetchone()
            replayed_row = conn.execute(
                "select source_path, source_uri, parsed_json from source_records where source_id=?",
                (replayed_id,),
            ).fetchone()
            rejected_row = conn.execute(
                "select raw_text, parsed_json from source_records where source_id=?",
                (rejected_id,),
            ).fetchone()
            replayed_parsed = {}
            if replayed_row is not None and isinstance(replayed_row["parsed_json"], str) and replayed_row["parsed_json"]:
                replayed_parsed = json.loads(replayed_row["parsed_json"])
            checks[mode] = {
                "safe_upkeeper_log": {
                    "raw_text_stored": bool(safe_row["raw_text"]) if safe_row is not None else False,
                    "parsed_json_stored": bool(safe_row["parsed_json"]) if safe_row is not None else False,
                },
                "unsafe_wrapper_observed": {
                    "raw_text_stored": bool(unsafe_row["raw_text"]) if unsafe_row is not None else False,
                    "parsed_json_stored": bool(unsafe_row["parsed_json"]) if unsafe_row is not None else False,
                },
                "rejected_transcript_pass": {
                    "raw_text_stored": bool(rejected_row["raw_text"]) if rejected_row is not None else False,
                    "parsed_json_stored": bool(rejected_row["parsed_json"]) if rejected_row is not None else False,
                },
                "imported_source_record": {
                    "raw_text_stored": bool(imported_source_record.get("raw_text")),
                    "parsed_json_stored": bool(imported_source_record.get("parsed_json")),
                },
                "replayed_upkeeper_log": {
                    "source_path_hashed": bool(replayed_row is not None and str(replayed_row["source_path"] or "").startswith(PASS_RESULT_PATH_HMAC_PREFIX)),
                    "source_uri_hashed": bool(replayed_row is not None and str(replayed_row["source_uri"] or "").startswith(PASS_RESULT_PATH_HMAC_PREFIX)),
                    "allowed_keys_only": set(replayed_parsed) <= UPKEEPER_LOG_SOURCE_SAFE_KEYS,
                    "quota_fields_removed": not any(
                        key in replayed_parsed
                        for key in (
                            "source",
                            "limit_id",
                            "limit_name",
                            "plan_type",
                            "snapshot_model_hint",
                            "primary_used",
                            "primary_reset",
                        )
                    ),
                },
                "replayed_upkeeper_log_raw": {
                    "source_hashed": "source_hmac=" in sanitized_quota_raw_line,
                    "limit_ids_hashed": "limit_id_hmac=" in sanitized_quota_raw_line and "limit_name_hmac=" in sanitized_quota_raw_line,
                    "quota_fields_removed": not any(
                        key in sanitized_quota_raw_line
                        for key in (
                            "source=/home/joe/.codex/sessions/2026/05/session.jsonl",
                            "limit_id=plan-123",
                            "limit_name='Example Plan'",
                            "plan_type=paid",
                            "snapshot_model_hint=gpt-5.5",
                            "primary_used='91%'",
                            "primary_reset='2026-05-13 01:00:00 -0700'",
                        )
                    ),
                },
                "imported_quota_source_record": {
                    "raw_text_stored": bool(imported_quota_source_record.get("raw_text")),
                    "source_path_hashed": str(imported_quota_source_record.get("source_path") or "").startswith(PASS_RESULT_PATH_HMAC_PREFIX),
                    "source_uri_hashed": str(imported_quota_source_record.get("source_uri") or "").startswith(PASS_RESULT_PATH_HMAC_PREFIX),
                    "raw_text_redacted": "source_hmac=" in str(imported_quota_source_record.get("raw_text") or "")
                    and "limit_id_hmac=" in str(imported_quota_source_record.get("raw_text") or "")
                    and "snapshot_model_hint" not in str(imported_quota_source_record.get("raw_text") or ""),
                },
            }
        finally:
            conn.execute(f"ROLLBACK TO raw_storage_{mode}")
            conn.execute(f"RELEASE raw_storage_{mode}")
    return checks


def doctor_result(args: argparse.Namespace) -> tuple[dict[str, Any], int]:
    root = Path(args.root).resolve()
    db_path = normalize_db_path(args.db, root)
    journal_mode = args.journal_mode
    result: dict[str, Any] = {
        "status": "ok",
        "db_path": str(db_path),
        "schema_version": SCHEMA_VERSION,
        "checks": {},
    }
    safety = path_safety(root, db_path, journal_mode)
    result["path_safety"] = safety
    if not safety["safe"] and not args.allow_unsafe_db:
        result["status"] = "unsafe_db_path"
        return result, EXIT_UNSAFE_DB_PATH
    result["checks"]["parent_exists"] = db_path.parent.exists()
    result["checks"]["parent_mode"] = oct(stat.S_IMODE(db_path.parent.stat().st_mode)) if db_path.parent.exists() else "missing"
    result["checks"]["db_exists"] = db_path.exists()
    if not db_path.exists():
        result["status"] = "db_unavailable"
        return result, EXIT_DB_UNAVAILABLE
    if not db_path.parent.exists():
        result["status"] = "db_unavailable"
        return result, EXIT_DB_UNAVAILABLE
    try:
        conn = connect(db_path, journal_mode, create_if_missing=False, emit_errors=False)
    except LatticeCommandError as exc:
        result["status"] = "db_unavailable"
        result["checks"]["open_error"] = str(exc)
        return result, exc.code
    try:
        result["checks"]["db_readable"] = True
        try:
            conn.execute("begin immediate")
            conn.execute("create temp table if not exists lattice_write_probe(value text)")
            conn.execute("insert into lattice_write_probe(value) values ('probe')")
            conn.execute("rollback")
            result["checks"]["write_transaction_rollback"] = True
            result["checks"]["db_writable"] = True
        except sqlite3.Error as exc:
            result["checks"]["db_writable"] = False
            result["checks"]["write_error"] = str(exc)
            try:
                conn.execute("rollback")
            except sqlite3.Error:
                pass
            result["status"] = "db_unavailable"
            return result, EXIT_DB_UNAVAILABLE
        user_version = int(conn.execute("PRAGMA user_version").fetchone()[0])
        result["checks"]["pragma_user_version"] = user_version
        fk_enabled = int(conn.execute("PRAGMA foreign_keys").fetchone()[0])
        result["checks"]["foreign_keys"] = fk_enabled
        if fk_enabled != 1:
            result["status"] = "integrity_failure"
            return result, EXIT_INTEGRITY
        table_names = {row["name"] for row in conn.execute("select name from sqlite_master where type='table'")}
        missing_tables = [table for table in REQUIRED_TABLES if table not in table_names]
        result["checks"]["required_tables_missing"] = missing_tables
        if missing_tables:
            result["status"] = "schema_mismatch"
            return result, EXIT_SCHEMA_MISMATCH
        ensure_source_record_identity_columns(conn)
        index_names = {row["name"] for row in conn.execute("select name from sqlite_master where type='index'")}
        missing_indexes = [index for index in REQUIRED_INDEXES if index not in index_names]
        result["checks"]["required_indexes_missing"] = missing_indexes
        if missing_indexes:
            result["status"] = "schema_mismatch"
            return result, EXIT_SCHEMA_MISMATCH
        meta = conn.execute("select value from schema_meta where key='schema_version'").fetchone()
        result["checks"]["schema_meta_version"] = meta["value"] if meta else None
        configured_raw_storage = configured_lattice_raw_storage()
        result["checks"]["raw_storage_requested"] = configured_raw_storage
        result["checks"]["raw_storage_effective"] = effective_lattice_raw_storage(configured_raw_storage)
        result["checks"]["raw_storage_valid"] = configured_raw_storage in RAW_STORAGE_COMPAT_MODES
        result["checks"]["raw_storage_enforcement"] = probe_raw_storage_enforcement(conn, root, ensure_repository(conn, root))
        review_summary_probe = probe_review_summary_parsing()
        result["checks"]["review_summary_parsing"] = review_summary_probe
        cycle_finish_probe = probe_cycle_finish_target_mismatch()
        result["checks"]["cycle_finish_target_mismatch"] = cycle_finish_probe
        report_only_cycle_probe = probe_cycle_finish_report_only_outcome()
        decorated_marker_probe = probe_cycle_finish_rejects_decorated_status_marker()
        result["checks"]["cycle_finish_report_only_outcome"] = report_only_cycle_probe
        result["checks"]["cycle_finish_rejects_decorated_status_marker"] = decorated_marker_probe
        change_note_ref_probe = probe_change_note_file_identity_validation()
        result["checks"]["change_note_file_identity_validation"] = change_note_ref_probe
        candidate_symlink_probe = probe_candidate_symlink_exclusion()
        result["checks"]["candidate_symlink_exclusion"] = candidate_symlink_probe
        candidate_text_sample_probe = probe_candidate_text_sample_limit()
        result["checks"]["candidate_text_sample_limit"] = candidate_text_sample_probe
        export_redaction_probe = probe_export_redaction()
        result["checks"]["export_redaction"] = export_redaction_probe
        if not all(bool(item.get("ok")) for item in review_summary_probe.values()):
            result["status"] = "integrity_failure"
            return result, EXIT_INTEGRITY
        if not bool(cycle_finish_probe.get("ok")):
            result["status"] = "integrity_failure"
            return result, EXIT_INTEGRITY
        if not bool(report_only_cycle_probe.get("ok")):
            result["status"] = "integrity_failure"
            return result, EXIT_INTEGRITY
        if not bool(decorated_marker_probe.get("ok")):
            result["status"] = "integrity_failure"
            return result, EXIT_INTEGRITY
        transient_temp_scope_probe = probe_cycle_finish_transient_artifact_scope()
        result["checks"]["cycle_finish_transient_artifact_scope"] = transient_temp_scope_probe
        if not bool(transient_temp_scope_probe.get("ok")):
            result["status"] = "integrity_failure"
            return result, EXIT_INTEGRITY
        if not all(bool(item.get("ok")) for item in change_note_ref_probe.values()):
            result["status"] = "integrity_failure"
            return result, EXIT_INTEGRITY
        if not bool(candidate_symlink_probe.get("ok")):
            result["status"] = "integrity_failure"
            return result, EXIT_INTEGRITY
        if not bool(candidate_text_sample_probe.get("ok")):
            result["status"] = "integrity_failure"
            return result, EXIT_INTEGRITY
        if not bool(export_redaction_probe.get("ok")):
            result["status"] = "integrity_failure"
            return result, EXIT_INTEGRITY
        if not meta or str(meta["value"]) != str(SCHEMA_VERSION) or user_version != SCHEMA_VERSION:
            result["status"] = "schema_mismatch"
            return result, EXIT_SCHEMA_MISMATCH
        fk_rows = [dict(row) for row in conn.execute("PRAGMA foreign_key_check")]
        result["checks"]["foreign_key_check_rows"] = fk_rows
        if fk_rows:
            result["status"] = "integrity_failure"
            return result, EXIT_INTEGRITY
        quick = conn.execute("PRAGMA quick_check").fetchone()[0]
        result["checks"]["quick_check"] = quick
        if str(quick).lower() != "ok":
            result["status"] = "integrity_failure"
            return result, EXIT_INTEGRITY
        if args.backup:
            backup_path = create_backup(conn, root, db_path, output=args.backup_output, allow_overwrite=True)
            result["checks"]["backup_path"] = str(backup_path)
            result["checks"]["backup_created"] = backup_path.exists()
    except sqlite3.Error as exc:
        result["status"] = "integrity_failure"
        result["checks"]["db_error"] = str(exc)
        return result, EXIT_INTEGRITY
    finally:
        conn.close()
    return result, EXIT_SUCCESS


def command_doctor(args: argparse.Namespace) -> int:
    result, code = doctor_result(args)
    print_json(result)
    return code


def record_cycle_link_from_env(conn: sqlite3.Connection, repo_id: int, cycle_pk: int, args: argparse.Namespace, source_id: int) -> None:
    parent_cycle_id = getattr(args, "parent_cycle_id", "") or os.environ.get("CODEX_PARENT_CYCLE_ID", "")
    child_cycle_id = getattr(args, "child_cycle_id", "") or os.environ.get("CODEX_SCREEN_FALLBACK_CHILD_ID", "")
    execution_origin = getattr(args, "execution_origin", "") or os.environ.get("CODEX_EXECUTION_ORIGIN", "")
    fallback_trigger = getattr(args, "fallback_trigger", "") or os.environ.get("CODEX_FALLBACK_TRIGGER", "")
    link_kind = ""
    if parent_cycle_id and str(parent_cycle_id).lower() not in {"none", "unknown"}:
        if execution_origin == "screen-child":
            link_kind = "screen_child"
        elif fallback_trigger:
            link_kind = "fallback"
        else:
            link_kind = "retry"
    if child_cycle_id and str(child_cycle_id).lower() not in {"none", "unknown"}:
        link_kind = "screen_child"
    if not link_kind:
        return
    parent_pk = None
    if parent_cycle_id:
        row = conn.execute(
            "select cycle_pk from cycles where repo_id=? and cycle_id=? order by cycle_pk desc limit 1",
            (repo_id, parent_cycle_id),
        ).fetchone()
        parent_pk = int(row["cycle_pk"]) if row else None
    child_pk = cycle_pk
    conn.execute(
        """
        insert into cycle_links(
          repo_id, parent_cycle_pk, child_cycle_pk, link_kind, trigger,
          parent_cycle_id_text, child_cycle_id_text, source_id, created_epoch
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            repo_id,
            parent_pk,
            child_pk,
            link_kind,
            fallback_trigger or None,
            parent_cycle_id or None,
            child_cycle_id or getattr(args, "cycle_id", None),
            source_id,
            epoch_now(),
        ),
    )


def command_record_cycle_start(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    db_path = normalize_db_path(args.db, root)
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    conn = connect_checked(root, db_path, args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    info = repo_git_info(root)
    context = repo_identity_context(root, info)
    with conn:
        repo_id = ensure_repository(conn, root)
        parsed = sanitize_cycle_start_fields(root, vars(args).copy())
        source_id = ensure_source_record(
            conn,
            root,
            repo_id,
            "wrapper_observed",
            raw_ref="cycle_start",
            parsed=parsed,
            raw_storage_mode=raw_storage_mode,
        )
        worktree_dirty = None
        if args.dirty_path_count is not None:
            worktree_dirty = 1 if int(args.dirty_path_count or 0) > 0 else 0
        verbose = verbose_metadata_enabled()
        config_value = args.config_file if verbose or not has_meaningful_value(args.config_file) else pass_result_path_hmac(root, str(args.config_file))
        cycle_pk = ensure_cycle(
            conn,
            repo_id,
            args.cycle_id,
            args.run_hash,
            source_id=source_id,
            start_epoch=args.start_epoch or epoch_now(),
            execution_origin=args.execution_origin,
            model=args.model if verbose else None,
            effort=args.effort if verbose else None,
            mode=args.mode if verbose else None,
            config_file=config_value,
            branch_name=protected_branch_name(context, args.branch_name or info["branch_name"]) if verbose else None,
            head_sha=(args.head_sha or info["head_sha"]) if verbose else None,
            head_tree_sha=(args.head_tree_sha or info["head_tree_sha"]) if verbose else None,
            upstream_ref=args.upstream_ref if verbose else None,
            worktree_dirty=worktree_dirty,
            dry_run=parse_bool_int(str(args.dry_run)) if args.dry_run is not None else None,
        )
        record_cycle_link_from_env(conn, repo_id, cycle_pk, args, source_id)
        record_worktree_snapshot(
            conn,
            root,
            repo_id,
            cycle_pk,
            "before_codex",
            source_id=source_id,
            untracked_files_mode=worktree_snapshot_untracked_files_mode(getattr(args, "worktree_untracked_files", None)),
        )
    print_json({"status": "ok", "cycle_pk": cycle_pk, "schema_version": SCHEMA_VERSION})
    return EXIT_SUCCESS


def record_worktree_snapshot(
    conn: sqlite3.Connection,
    root: Path,
    repo_id: int,
    cycle_pk: int | None,
    snapshot_kind: str,
    *,
    source_id: int | None = None,
    untracked_files_mode: str = "no",
) -> int:
    observed = epoch_now()
    info = repo_git_info(root)
    context = repo_identity_context(root, info)
    head_sha = info["head_sha"]
    branch = protected_branch_name(context, info["branch_name"])
    raw = b""
    untracked_files_mode = worktree_snapshot_untracked_files_mode(untracked_files_mode)
    include_path_inventory = untracked_files_mode in {"normal", "all"}
    status_source = f"git status --porcelain=v1 -z --untracked-files={untracked_files_mode}"
    try:
        raw = subprocess.check_output(
            ["git", "-C", str(root), "status", "--porcelain=v1", "-z", f"--untracked-files={untracked_files_mode}"]
        )
    except (OSError, subprocess.CalledProcessError):
        raw = b""
    entries = []
    for status_code, path, old_path in parse_git_porcelain_v1_z_entries(raw):
        if not path or is_runtime_artifact_path(path):
            continue
        if old_path and is_runtime_artifact_path(old_path):
            continue
        entries.append((status_code, path, old_path))
    tracked = 0
    untracked = 0
    for status_code, path, _old_path in entries:
        if status_code == "??":
            untracked += 1
        else:
            tracked += 1
    cur = conn.execute(
        """
        insert into worktree_snapshots(
          repo_id, cycle_pk, snapshot_kind, observed_epoch, git_head_sha, branch_name,
          dirty_path_count, tracked_modified_path_count, untracked_path_count, source_id, details_json
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            repo_id,
            cycle_pk,
            snapshot_kind,
            observed,
            head_sha or None,
            branch or None,
            len(entries),
            tracked,
            untracked,
            source_id,
            json_dumps({"source": status_source}),
        ),
    )
    snapshot_id = int(cur.lastrowid)
    for status_code, path, old_path in entries:
        if not include_path_inventory:
            continue
        if worktree_snapshot_path_is_sensitive(path) or (old_path and worktree_snapshot_path_is_sensitive(old_path)):
            continue
        meta = live_file_metadata(root, path)
        stored_path = pass_result_path_hmac(root, path)
        stored_old_path = pass_result_path_hmac(root, old_path) if old_path else None
        if not stored_path:
            continue
        conn.execute(
            """
            insert into worktree_snapshot_paths(
              worktree_snapshot_id, file_id, path, path_hmac, path_class, status, old_path, old_path_hmac, old_path_class, head_blob,
              worktree_hash, size_bytes, mtime_epoch, mtime_ns
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                snapshot_id,
                None,
                stored_path,
                stored_path,
                worktree_snapshot_path_class(status_code),
                status_code,
                stored_old_path,
                stored_old_path,
                worktree_snapshot_path_class(status_code, is_old=True),
                meta.get("head_blob"),
                meta.get("worktree_hash"),
                meta.get("size_bytes"),
                meta.get("mtime_epoch"),
                meta.get("mtime_ns"),
            ),
        )
    return snapshot_id


def latest_worktree_snapshot_id(
    conn: sqlite3.Connection,
    *,
    repo_id: int,
    cycle_pk: int | None,
    snapshot_kind: str,
) -> int | None:
    if cycle_pk is None:
        return None
    row = conn.execute(
        """
        select worktree_snapshot_id
          from worktree_snapshots
         where repo_id=? and cycle_pk=? and snapshot_kind=?
         order by observed_epoch desc, worktree_snapshot_id desc
         limit 1
        """,
        (repo_id, cycle_pk, snapshot_kind),
    ).fetchone()
    return int(row["worktree_snapshot_id"]) if row else None


def worktree_snapshot_path_row(
    conn: sqlite3.Connection,
    *,
    repo_id: int,
    cycle_pk: int | None,
    path: str,
    snapshot_kind: str,
) -> sqlite3.Row | None:
    snapshot_id = latest_worktree_snapshot_id(
        conn,
        repo_id=repo_id,
        cycle_pk=cycle_pk,
        snapshot_kind=snapshot_kind,
    )
    if snapshot_id is None:
        return None
    return conn.execute(
        """
        select p.*
        from worktree_snapshot_paths p
        join worktree_snapshots s on s.worktree_snapshot_id=p.worktree_snapshot_id
        where s.repo_id=? and p.worktree_snapshot_id=? and p.path=?
        order by p.worktree_snapshot_path_id desc
        limit 1
        """,
        (repo_id, snapshot_id, stored_rel_path(path)),
    ).fetchone()


def worktree_snapshot_path_map(conn: sqlite3.Connection, snapshot_id: int | None) -> dict[str, sqlite3.Row]:
    if snapshot_id is None:
        return {}
    rows = conn.execute(
        """
        select *
          from worktree_snapshot_paths
         where worktree_snapshot_id=?
        """,
        (snapshot_id,),
    ).fetchall()
    return {operational_rel_path(str(row["path"])): row for row in rows}


def worktree_snapshot(conn: sqlite3.Connection, snapshot_id: int | None) -> sqlite3.Row | None:
    if snapshot_id is None:
        return None
    return conn.execute(
        """
        select *
          from worktree_snapshots
         where worktree_snapshot_id=?
        """,
        (snapshot_id,),
    ).fetchone()


def changed_paths_from_head(
    root: Path,
    before_head: str | None,
    after_head: str | None,
) -> set[str]:
    if not before_head or not after_head:
        return set()
    if before_head == "none" or after_head == "none":
        return set()
    if before_head == after_head:
        return set()
    try:
        raw = subprocess.check_output(
            ["git", "-C", str(root), "diff", "--name-only", "-z", before_head, after_head],
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        return set()
    paths = decode_git_output(raw).split("\0")
    return {path for path in paths if path}


def record_worktree_delta_events(
    conn: sqlite3.Connection,
    *,
    repo_id: int,
    root: Path,
    cycle_pk: int | None,
    source_id: int | None,
    after_snapshot_id: int,
) -> None:
    before_snapshot_id = latest_worktree_snapshot_id(
        conn,
        repo_id=repo_id,
        cycle_pk=cycle_pk,
        snapshot_kind="before_codex",
    )
    before_snapshot = worktree_snapshot(conn, before_snapshot_id)
    after_snapshot = worktree_snapshot(conn, after_snapshot_id)
    before_paths = worktree_snapshot_path_map(conn, before_snapshot_id)
    after_paths = worktree_snapshot_path_map(conn, after_snapshot_id)
    commit_changed_paths = changed_paths_from_head(
        root,
        before_snapshot["git_head_sha"] if before_snapshot else None,
        after_snapshot["git_head_sha"] if after_snapshot else None,
    ) if before_snapshot is not None and after_snapshot is not None else set()

    # If there is no pre-Codex snapshot, we cannot classify per-file diffs safely.
    # Record known dirty files as a special baseline-missing signal and avoid
    # emitting normal changed events that could be misattributed to this cycle.
    if before_snapshot is None:
        for path, after in after_paths.items():
            after_status = after["status"] if after else "clean"
            if after_status == "clean":
                continue
            file_id = after["file_id"] if after else None
            if file_id is None:
                file_id = ensure_file(conn, repo_id, path, source_id=source_id)
            record_file_event(
                conn,
                repo_id,
                "dirty_state_observed_without_baseline",
                file_id=file_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                path=path,
                details={
                    "source": "worktree_snapshot_delta",
                    "before_worktree_snapshot_id": before_snapshot_id,
                    "after_worktree_snapshot_id": after_snapshot_id,
                    "before_status": "unknown",
                    "after_status": after_status,
                    "before_worktree_hash": None,
                    "after_worktree_hash": after["worktree_hash"] if after else None,
                    "before_worktree_head_sha": None,
                    "after_worktree_head_sha": after_snapshot["git_head_sha"] if after_snapshot else None,
                    "reason": "missing_before_snapshot",
                },
            )
        return

    all_paths = sorted(set(before_paths) | set(after_paths))
    all_paths.extend(sorted(commit_changed_paths - set(all_paths)))

    for path in all_paths:
        before = before_paths.get(path)
        after = after_paths.get(path)
        before_hash = before["worktree_hash"] if before else None
        after_hash = after["worktree_hash"] if after else None
        before_status = before["status"] if before else "clean"
        after_status = after["status"] if after else "clean"
        if before and after and before_status == after_status and before_hash == after_hash:
            continue
        file_id = after["file_id"] if after else before["file_id"] if before else None
        if file_id is None:
            file_id = ensure_file(conn, repo_id, path, source_id=source_id)
        record_file_event(
            conn,
            repo_id,
            "changed",
            file_id=file_id,
            cycle_pk=cycle_pk,
            source_id=source_id,
            path=path,
            details={
                "source": "worktree_snapshot_delta",
                "before_worktree_snapshot_id": before_snapshot_id,
                "after_worktree_snapshot_id": after_snapshot_id,
                "before_status": before_status,
                "after_status": after_status,
                "before_worktree_hash": before_hash,
                "after_worktree_hash": after_hash,
                "before_worktree_head_sha": before_snapshot["git_head_sha"] if before_snapshot else None,
                "after_worktree_head_sha": after_snapshot["git_head_sha"] if after_snapshot else None,
                "head_delta_source": "git diff" if path in commit_changed_paths else None,
            },
        )


def command_record_worktree_snapshot(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    conn = connect_checked(root, normalize_db_path(args.db, root), args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(
            conn,
            root,
            repo_id,
            "wrapper_observed",
            raw_ref=f"worktree_snapshot:{args.snapshot_kind}",
            raw_storage_mode=raw_storage_mode,
        )
        cycle_pk = None
        if args.cycle_id and args.run_hash:
            cycle_pk = ensure_cycle(conn, repo_id, args.cycle_id, args.run_hash, source_id=source_id)
        snapshot_id = record_worktree_snapshot(
            conn,
            root,
            repo_id,
            cycle_pk,
            args.snapshot_kind,
            source_id=source_id,
            untracked_files_mode=worktree_snapshot_untracked_files_mode(getattr(args, "worktree_untracked_files", None)),
        )
    print_json({"status": "ok", "worktree_snapshot_id": snapshot_id})
    return EXIT_SUCCESS


def command_record_preselect(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    conn = connect_checked(root, normalize_db_path(args.db, root), args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    selection = parse_key_value_file(Path(args.selection_file)) if args.selection_file else parse_key_value_text(sys.stdin.read())
    candidate_rows = load_jsonl(Path(args.candidate_file)) if args.candidate_file else []
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(
            conn,
            root,
            repo_id,
            "wrapper_observed",
            raw_ref="preselect",
            raw_text=json_dumps(selection),
            parsed={"selection": selection, "candidate_count": len(candidate_rows)},
            raw_storage_mode=raw_storage_mode,
        )
        cycle_pk = ensure_cycle(conn, repo_id, args.cycle_id, args.run_hash, source_id=source_id)
        selected_path = external_rel_path(selection.get("path", ""))
        stored_selected_path = stored_rel_path(selected_path) if selected_path else ""
        selected_file_state = "active"
        selected_content_state = selection.get("content_state")
        if selected_path:
            _, selected_file_safety = source_safe_file_stat(root, selected_path)
            if selected_file_safety:
                selected_file_state = "missing"
                selected_content_state = "missing"
        selected_file_id = (
            ensure_file(conn, repo_id, selected_path, state=selected_file_state, source_id=source_id) if selected_path else None
        )
        mode = selection.get("selection_mode", "unknown")
        gate = selector_priority_gate(mode)
        selected_rank = None
        eligible_count = int(selection.get("eligible_count") or 0)
        seen_candidates: dict[str, dict[str, Any]] = {}
        for index, row in enumerate(candidate_rows, start=1):
            path = external_rel_path(str(row.get("path", "")))
            if not path:
                continue
            state = str(row.get("candidate_state", "eligible"))
            state_priority = CANDIDATE_STATE_PRIORITY.get(state, CANDIDATE_STATE_PRIORITY["eligible"])
            prior = seen_candidates.get(path)
            if prior is None:
                seen_candidates[path] = {"index": index, "state_priority": state_priority, "row": row}
            elif state_priority > prior["state_priority"]:
                prior["index"] = index
                prior["state_priority"] = state_priority
                prior["row"] = row
        deduped_candidates: list[dict[str, Any]] = []
        for path, info in seen_candidates.items():
            row = dict(info["row"])
            row["path"] = path
            row["_lattice_input_index"] = info["index"]
            if path == selected_path:
                row["candidate_state"] = "selected"
            deduped_candidates.append(row)
        for row in deduped_candidates:
            if row.get("path") == selected_path:
                selected_rank = int(row.get("rank") or row.get("_lattice_input_index", 1))
                break
        if selected_rank is None and selected_path:
            selected_rank = 1
        calculated_excluded_count = len([r for r in deduped_candidates if r.get("candidate_state") == "excluded"])
        calculated_eligible_count = len(
            [r for r in deduped_candidates if r.get("candidate_state") in {"eligible", "selected"}]
        )
        if not eligible_count:
            eligible_count = calculated_eligible_count
        excluded_count = calculated_excluded_count
        cur = conn.execute(
            """
            insert into selection_runs(
              repo_id, cycle_pk, selector_version, source_safe_boundary_version,
              mode_requested, mode_effective, priority_gate, generated_epoch,
              git_head_sha, dirty_path_count, eligible_count, excluded_count,
              incomplete, incomplete_reason, selected_file_id, selected_path,
              selected_rank, details_json
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                repo_id,
                cycle_pk,
                args.selector_version,
                args.source_safe_boundary_version,
                args.selection_mode or selection.get("selection_order") or "oldest-mtime",
                mode,
                gate,
                epoch_now(),
                repo_git_info(root)["head_sha"] or None,
                None,
                eligible_count,
                excluded_count,
                0,
                None,
                selected_file_id,
                stored_selected_path or None,
                selected_rank,
                json_dumps(selection),
            ),
        )
        selection_run_id = int(cur.lastrowid)
        if deduped_candidates:
            for row in deduped_candidates:
                path = row.get("path")
                state = str(row.get("candidate_state", "eligible"))
                file_state = "active"
                if path == selected_path:
                    state = "selected"
                    file_state = selected_file_state
                file_id = ensure_file(conn, repo_id, path, state=file_state, source_id=source_id) if state != "forced_missing" else None
                rank = row.get("rank")
                if state in {"eligible", "selected"} and rank is None:
                    rank = row.get("_lattice_input_index", 1)
                content_state = row.get("content_state") if path != selected_path else (selected_content_state if selected_content_state is not None else row.get("content_state"))
                conn.execute(
                    """
                    insert or ignore into selection_candidates(
                      selection_run_id, file_id, path, candidate_state, rank, mtime_epoch,
                      git_status, content_state, head_blob, worktree_hash, exclusion_reason, score_json, source_id
                    ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        selection_run_id,
                        file_id,
                        stored_rel_path(path),
                        state,
                        rank,
                        row.get("mtime_epoch"),
                        row.get("git_status"),
                        content_state,
                        row.get("head_blob"),
                        row.get("worktree_hash"),
                        row.get("exclusion_reason") or None,
                        json_dumps(row.get("score", row.get("score_json"))) if row.get("score") is not None or row.get("score_json") is not None else None,
                        source_id,
                    ),
                )
                event_kind = "candidate_seen"
                if state == "excluded":
                    event_kind = "candidate_excluded"
                elif state == "selected":
                    event_kind = "selected"
                record_file_event(
                    conn,
                    repo_id,
                    event_kind,
                    file_id=file_id,
                    cycle_pk=cycle_pk,
                    source_id=source_id,
                    path=path,
                    details=row,
                )
        elif selected_path:
            conn.execute(
                """
                insert or ignore into selection_candidates(
                  selection_run_id, file_id, path, candidate_state, rank, mtime_epoch,
                  git_status, content_state, head_blob, worktree_hash, source_id
                ) values (?, ?, ?, 'selected', 1, ?, ?, ?, ?, ?, ?)
                """,
                (
                    selection_run_id,
                    selected_file_id,
                    stored_selected_path,
                    int(selection.get("epoch") or 0) or None,
                    selection.get("git_status"),
                    selected_content_state,
                    selection.get("head_blob"),
                    selection.get("worktree_hash"),
                    source_id,
                ),
            )
        if selected_path:
            before_snapshot_id = insert_file_snapshot(conn, root, repo_id, selected_path, file_id=selected_file_id, source_id=source_id)
            record_file_event(
                conn,
                repo_id,
                "snapshot_before",
                file_id=selected_file_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                path=selected_path,
                details={"snapshot_id": before_snapshot_id},
            )
            conn.execute(
                "update cycles set selected_file_id=?, selected_path=?, selection_basis=? where cycle_pk=?",
                (selected_file_id, stored_selected_path, selection.get("selection_basis"), cycle_pk),
            )
            if selection.get("content_state") == "differs_from_head" or selection.get("git_status") not in {"", "clean", None}:
                record_file_event(
                    conn,
                    repo_id,
                    "dirty_baseline",
                    file_id=selected_file_id,
                    cycle_pk=cycle_pk,
                    source_id=source_id,
                    path=selected_path,
                    details=selection,
                )
    print_json({"status": "ok", "selection_run_id": selection_run_id, "selected_path": stored_selected_path})
    return EXIT_SUCCESS


def parse_review_summary_file(path: Path, repo_root: Path | None = None) -> dict[str, str]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    outcome = extract_review_outcome(text)
    selected_file = ""
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not re.search(r"\b(selected|target|review target)\b", line, re.I):
            continue
        if not re.search(r"\b(file|target)\b", line, re.I):
            continue
        md = re.search(r"\]\(([^)]+)\)", line)
        bt = re.search(r"`([^`]+)`", line)
        candidate = ""
        if md:
            candidate = normalize_review_summary_target(md.group(1), repo_root)
        elif bt:
            candidate = normalize_review_summary_target(bt.group(1), repo_root)
        elif ":" in line:
            parsed_candidate_match = re.search(
                r"(?ix)^\s*(?:selected\s+file|selected\s+target|target\s+file|review\s+target\s+file|review\s+target|target)\s*[:=]\s*(.+)$",
                line,
            )
            if parsed_candidate_match:
                candidate = normalize_review_summary_target(parsed_candidate_match.group(1), repo_root)
        if candidate:
            selected_file = candidate
        if selected_file:
            break
    return {"review_outcome": outcome, "selected_file": selected_file}


def extract_review_outcome(text: str) -> str:
    outcome = ""
    in_fence = False
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence or line.startswith(">"):
            continue
        match = REVIEW_OUTCOME_LINE_PATTERN.match(line)
        if match:
            outcome = match.group(1)
    return outcome


def extract_review_status_marker_from_text(text: str) -> str:
    in_fence = False
    final_line = ""
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        final_line = line
    if not final_line:
        return ""
    match = UPKEEPER_STATUS_CONTRACT_LINE.match(final_line)
    if not match:
        return ""
    marker = match.group(1)
    return UPKEEPER_STATUS_ALIAS.get(marker, marker)


def parse_review_status_marker(path: Path) -> str:
    try:
        return extract_review_status_marker_from_text(path.read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return ""


def normalize_review_summary_target(raw_target: str, repo_root: Path | None = None) -> str:
    text = raw_target.strip().strip("<>")
    if not text:
        return ""
    if re.search(r"^[A-Za-z][A-Za-z0-9+\-.]*:/", text):
        return ""
    normalized = normalize_change_note_ref(text)
    if normalized:
        return normalized
    if re.search(r"^[A-Za-z][A-Za-z0-9+\-.]*://", text):
        return ""

    candidates = [text]
    line_match = re.fullmatch(r"(.+):([0-9]+)", text)
    if line_match:
        # Only treat ":<line>" as a line suffix when the pre-colon path is not
        # URL-like and does not contain a repo-relative colon-bearing filename.
        line_target = line_match.group(1)
        if Path(line_target).is_absolute() or re.match(r"^[A-Za-z]:[\\/]", line_target) or (
            ":" not in line_target and "://" not in text
        ):
            candidates.append(line_target)

    if repo_root is None:
        return ""

    repo_root = repo_root.resolve()
    for candidate_text in candidates:
        candidate_path = Path(candidate_text)
        if not candidate_path.is_absolute() or not candidate_path.exists():
            continue
        try:
            repo_relative = candidate_path.resolve(strict=False).relative_to(repo_root)
        except (OSError, RuntimeError, ValueError):
            continue
        # Clickable local file links may append a :line suffix, but the repo
        # identity must remain the existing file path rather than a truncated
        # or synthetic colon split.
        normalized = normalize_change_note_ref(repo_relative.as_posix())
        if normalized:
            return normalized
    return ""


def probe_review_summary_parsing() -> dict[str, Any]:
    cases: dict[str, tuple[str, str, str]] = {
        "contract_outcome": (
            "selected file: `tools/upkeeper_lattice.py`\nUPKEEPER_REVIEW_OUTCOME=REVIEWED_AND_REPORTED\n",
            "tools/upkeeper_lattice.py",
            "REVIEWED_AND_REPORTED",
        ),
        "bare_outcome": (
            "Selected file: `tools/upkeeper_lattice.py`\nREVIEWED_AND_REPORTED\n",
            "tools/upkeeper_lattice.py",
            "REVIEWED_AND_REPORTED",
        ),
        "legacy_status_phrase": (
            "Selected file: `tools/upkeeper_lattice.py`\nReview outcome: REVIEWED_AND_REPORTED\n",
            "tools/upkeeper_lattice.py",
            "",
        ),
        "legacy_marker_in_body": (
            "Allowed outcomes include REVIEWED_CLEAN and REVIEWED_AND_REPORTED.\n"
            "Final status: REVIEWED_AND_FIXED\n",
            "",
            "",
        ),
        "quoted_marker": (
            "> UPKEEPER_REVIEW_OUTCOME=REVIEWED_AND_REPORTED\nSelected file: `tools/upkeeper_lattice.py`\n",
            "tools/upkeeper_lattice.py",
            "",
        ),
        "fenced_marker": (
            "```text\nUPKEEPER_REVIEW_OUTCOME=REVIEWED_AND_REPORTED\n```\nSelected file: `tools/upkeeper_lattice.py`\n",
            "tools/upkeeper_lattice.py",
            "",
        ),
        "inline_quote_marker_ignored": (
            "Example instruction: `UPKEEPER_REVIEW_OUTCOME=REVIEWED_CLEAN` should never count.\n"
            "Selected file: `tools/upkeeper_lattice.py`\n",
            "tools/upkeeper_lattice.py",
            "",
        ),
        "colon_bearing_path": (
            "Selected file: pkg:tools/build.sh\nUPKEEPER_REVIEW_OUTCOME = REVIEWED_AND_FIXED\n",
            "pkg:tools/build.sh",
            "REVIEWED_AND_FIXED",
        ),
        "markdown_colon_bearing_path": (
            "Selected file: [pkg:tools/build.sh](pkg:tools/build.sh)\nUPKEEPER_REVIEW_OUTCOME=REVIEWED_AND_REPORTED\n",
            "pkg:tools/build.sh",
            "REVIEWED_AND_REPORTED",
        ),
        "markdown_scheme_rejected": (
            "Selected file: [remote](https://example.invalid/file.sh)\nUPKEEPER_REVIEW_OUTCOME=REVIEWED_CLEAN\n",
            "",
            "REVIEWED_CLEAN",
        ),
        "markdown_scheme_with_line_suffix_rejected": (
            "Selected file: [remote](https://example.invalid/file.sh:443)\nUPKEEPER_REVIEW_OUTCOME=REVIEWED_CLEAN\n",
            "",
            "REVIEWED_CLEAN",
        ),
        "markdown_scheme_single_slash_rejected": (
            "Selected file: [remote](https:/example.invalid/file.sh)\nUPKEEPER_REVIEW_OUTCOME=REVIEWED_CLEAN\n",
            "",
            "REVIEWED_CLEAN",
        ),
    }
    results: dict[str, Any] = {}
    with tempfile.TemporaryDirectory(prefix="upkeeper-lattice-review-summary-") as tmpdir:
        root = Path(tmpdir)
        (root / "pkg:tools").mkdir(parents=True, exist_ok=True)
        absolute_line_target = root / "pkg:tools" / "build.sh"
        absolute_line_target.write_text("#!/bin/sh\n", encoding="utf-8")
        cases["markdown_absolute_line_suffix"] = (
            f"Selected file: [pkg:tools/build.sh]({absolute_line_target}:12)\nUPKEEPER_REVIEW_OUTCOME=REVIEWED_AND_FIXED\n",
            "pkg:tools/build.sh",
            "REVIEWED_AND_FIXED",
        )
        for name, (content, expected_selected, expected_outcome) in cases.items():
            path = root / f"{name}.txt"
            path.write_text(content, encoding="utf-8")
            parsed = parse_review_summary_file(path, root)
            actual_selected = parsed.get("selected_file", "")
            actual_outcome = parsed.get("review_outcome", "")
            results[name] = {
                "expected_selected_file": expected_selected,
                "actual_selected_file": actual_selected,
                "expected_review_outcome": expected_outcome,
                "actual_review_outcome": actual_outcome,
                "ok": actual_selected == expected_selected and actual_outcome == expected_outcome,
            }
    return results


def probe_cycle_finish_target_mismatch() -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="upkeeper-lattice-cycle-finish-") as tmpdir:
        root = Path(tmpdir)
        selected_path = "tools/original.py"
        reported_path = "tools/replacement.py"
        try:
            subprocess.run(
                ["git", "init", "-q", str(root)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except (OSError, subprocess.CalledProcessError):
            pass
        (root / "tools").mkdir(parents=True, exist_ok=True)
        (root / "runtime").mkdir(parents=True, exist_ok=True)
        (root / selected_path).write_text("print('original')\n", encoding="utf-8")
        (root / reported_path).write_text("print('replacement')\n", encoding="utf-8")
        review_path = root / "runtime" / "last-message.txt"
        review_path.write_text(
            "Selected file: `tools/replacement.py`\nReview outcome: REVIEWED_AND_FIXED\n",
            encoding="utf-8",
        )
        db_path = root / "lattice.sqlite3"
        conn = connect_checked(root, db_path, "wal", allow_unsafe_db=True, create_parent=True, create_if_missing=True)
        try:
            init_schema(conn, root, raw_storage_mode="minimal")
        finally:
            conn.close()
        args = argparse.Namespace(
            root=str(root),
            db=str(db_path),
            journal_mode="wal",
            allow_unsafe_db=True,
            raw_storage_mode="minimal",
            cycle_id="cycle-mismatch",
            run_hash="run-mismatch",
            status_marker="WORK_DONE",
            review_outcome=None,
            review_selected_path=None,
            codex_exit=0,
            wrapper_exit=0,
            finish_reason="work_done",
            finish_level="info",
            codex_exec_started=1,
            dry_run="1",
            selected_path=selected_path,
            last_message_file=str(review_path),
            transcript_path=None,
            compiled_prompt_path=None,
            log_path=None,
            snapshot_kind="after_codex",
            end_epoch=1234567890,
        )
        with contextlib.redirect_stdout(io.StringIO()):
            command_record_cycle_finish(args)
        conn = connect_checked(root, db_path, "wal", allow_unsafe_db=True)
        try:
            cycle = conn.execute(
                """
                select status_marker, review_outcome, finish_reason, finish_level, selected_path
                  from cycles
                 where cycle_id=? and run_hash=?
                """,
                ("cycle-mismatch", "run-mismatch"),
            ).fetchone()
            rejected = conn.execute(
                """
                select event_kind, path, details_json
                  from file_events
                 where event_kind='target_substitution_rejected'
                 order by event_id desc
                 limit 1
                """
            ).fetchone()
            substituted_count = int(
                conn.execute("select count(*) from file_events where event_kind='target_substituted'").fetchone()[0]
            )
        finally:
            conn.close()
    details = json.loads(rejected["details_json"]) if rejected and rejected["details_json"] else {}
    ok = bool(cycle) and bool(rejected) and substituted_count == 0
    if cycle:
        ok = ok and cycle["status_marker"] == "BLOCKED"
        ok = ok and cycle["review_outcome"] == "STOPPED_ON_BLOCKER"
        ok = ok and cycle["finish_reason"] == "selected_path_mismatch"
        ok = ok and cycle["finish_level"] == "error"
        ok = ok and cycle["selected_path"] == selected_path
    ok = ok and details.get("preselected_path") == selected_path
    ok = ok and details.get("reported_selected_path") == reported_path
    return {
        "expected_selected_path": selected_path,
        "reported_selected_path": reported_path,
        "actual_selected_path": cycle["selected_path"] if cycle else None,
        "status_marker": cycle["status_marker"] if cycle else None,
        "review_outcome": cycle["review_outcome"] if cycle else None,
        "finish_reason": cycle["finish_reason"] if cycle else None,
        "finish_level": cycle["finish_level"] if cycle else None,
        "target_substituted_count": substituted_count,
        "rejected_event_kind": rejected["event_kind"] if rejected else None,
        "rejected_event_path": rejected["path"] if rejected else None,
        "ok": ok,
    }


def probe_cycle_finish_transient_artifact_scope() -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="upkeeper-lattice-cycle-finish-scope-") as tmpdir:
        root = Path(tmpdir).resolve()
        selected_path = "tools/selected.py"
        try:
            subprocess.run(["git", "init", "-q", str(root)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.CalledProcessError):
            pass
        (root / "tools").mkdir(parents=True, exist_ok=True)
        (root / "runtime").mkdir(parents=True, exist_ok=True)
        (root / selected_path).write_text("print('selected')\n", encoding="utf-8")

        temp_root = Path(tempfile.gettempdir()).resolve()
        transient_dir = Path(tempfile.mkdtemp(prefix="upkeeper-", dir=str(temp_root)))
        compiled_prompt_path = transient_dir / "compiled-prompt.probe"
        last_message_path = transient_dir / "last-message.probe"
        review_path = last_message_path
        compiled_prompt_path.write_text("probe compiled prompt artifact\n", encoding="utf-8")
        last_message_path.write_text(
            "Selected file: `tools/selected.py`\nREVIEWED_AND_REPORTED\n",
            encoding="utf-8",
        )

        db_path = root / "lattice.sqlite3"
        conn = connect_checked(root, db_path, "wal", allow_unsafe_db=True, create_parent=True, create_if_missing=True)
        try:
            init_schema(conn, root, raw_storage_mode="minimal")
        finally:
            conn.close()
        args = argparse.Namespace(
            root=str(root),
            db=str(db_path),
            journal_mode="wal",
            allow_unsafe_db=True,
            raw_storage_mode="minimal",
            cycle_id="cycle-temp-scope",
            run_hash="run-temp-scope",
            status_marker="WORK_DONE",
            review_outcome=None,
            review_selected_path=None,
            codex_exit=0,
            wrapper_exit=0,
            finish_reason="work_done",
            finish_level="info",
            codex_exec_started=1,
            dry_run="1",
            selected_path=selected_path,
            last_message_file=str(review_path),
            transcript_path=None,
            compiled_prompt_path=str(compiled_prompt_path),
            log_path=None,
            snapshot_kind="after_codex",
            end_epoch=1234567890,
        )
        cycle = None
        compiled = None
        last_message = None
        code = 0
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                command_record_cycle_finish(args)
            code = 0
        except LatticeCommandError as exc:
            code = exc.code
        else:
            conn = connect_checked(root, db_path, "wal", allow_unsafe_db=True)
            try:
                repo_id = ensure_repository(conn, root)
                cycle = conn.execute(
                    """
                    select cycle_pk
                      from cycles
                     where cycle_id=? and run_hash=?
                    """,
                    ("cycle-temp-scope", "run-temp-scope"),
                ).fetchone()
                compiled = conn.execute(
                    """
                    select path
                      from artifact_refs
                     where repo_id=? and cycle_pk=? and artifact_kind='compiled_prompt'
                    """,
                    (repo_id, cycle["cycle_pk"]),
                ).fetchone()
                last_message = conn.execute(
                    """
                    select path
                      from artifact_refs
                     where repo_id=? and cycle_pk=? and artifact_kind='last_message'
                    """,
                    (repo_id, cycle["cycle_pk"]),
                ).fetchone()
            finally:
                conn.close()
        finally:
            for candidate in (compiled_prompt_path, last_message_path):
                try:
                    candidate.unlink()
                except OSError:
                    pass
            try:
                transient_dir.rmdir()
            except OSError:
                pass
    ok = code == 0
    if cycle:
        ok = ok and bool(compiled) and isinstance(compiled["path"], str) and compiled["path"].startswith(PASS_RESULT_PATH_HMAC_PREFIX)
        ok = ok and bool(last_message) and isinstance(last_message["path"], str) and last_message["path"].startswith(PASS_RESULT_PATH_HMAC_PREFIX)
    return {
        "cycle_id": "cycle-temp-scope",
        "run_hash": "run-temp-scope",
        "cycle_return_code": code,
        "compiled_prompt_path": compiled["path"] if compiled else None,
        "last_message_path": last_message["path"] if last_message else None,
        "ok": ok,
    }


def probe_cycle_finish_report_only_outcome() -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="upkeeper-lattice-cycle-finish-report-only-") as tmpdir:
        root = Path(tmpdir)
        selected_path = "tools/report-only.py"
        try:
            subprocess.run(
                ["git", "init", "-q", str(root)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except (OSError, subprocess.CalledProcessError):
            pass
        (root / "tools").mkdir(parents=True, exist_ok=True)
        (root / "runtime").mkdir(parents=True, exist_ok=True)
        (root / selected_path).write_text("print('report only')\n", encoding="utf-8")
        review_path = root / "runtime" / "last-message.txt"
        review_path.write_text(
            "Selected file: `tools/report-only.py`\nREVIEWED_AND_REPORTED\nUPKEEPER_STATUS: WORK_DONE\n",
            encoding="utf-8",
        )
        db_path = root / "lattice.sqlite3"
        conn = connect_checked(root, db_path, "wal", allow_unsafe_db=True, create_parent=True, create_if_missing=True)
        try:
            init_schema(conn, root, raw_storage_mode="minimal")
        finally:
            conn.close()
        args = argparse.Namespace(
            root=str(root),
            db=str(db_path),
            journal_mode="wal",
            allow_unsafe_db=True,
            raw_storage_mode="minimal",
            cycle_id="cycle-report-only",
            run_hash="run-report-only",
            status_marker="WORK_DONE",
            review_outcome=None,
            review_selected_path=None,
            codex_exit=0,
            wrapper_exit=0,
            finish_reason="work_done",
            finish_level="info",
            codex_exec_started=1,
            dry_run="1",
            selected_path=selected_path,
            last_message_file=str(review_path),
            transcript_path=None,
            compiled_prompt_path=None,
            log_path=None,
            snapshot_kind="after_codex",
            end_epoch=1234567890,
        )
        with contextlib.redirect_stdout(io.StringIO()):
            command_record_cycle_finish(args)
        conn = connect_checked(root, db_path, "wal", allow_unsafe_db=True)
        try:
            cycle = conn.execute(
                """
                select status_marker, review_outcome, finish_reason, finish_level, selected_path
                  from cycles
                 where cycle_id=? and run_hash=?
                """,
                ("cycle-report-only", "run-report-only"),
            ).fetchone()
        finally:
            conn.close()
    ok = bool(cycle)
    if cycle:
        ok = ok and cycle["status_marker"] == "WORK_DONE"
        ok = ok and cycle["review_outcome"] == "REVIEWED_AND_REPORTED"
        ok = ok and cycle["finish_reason"] == "work_done"
        ok = ok and cycle["finish_level"] == "info"
        ok = ok and cycle["selected_path"] == selected_path
    return {
        "selected_path": selected_path,
        "status_marker": cycle["status_marker"] if cycle else None,
        "review_outcome": cycle["review_outcome"] if cycle else None,
        "finish_reason": cycle["finish_reason"] if cycle else None,
        "finish_level": cycle["finish_level"] if cycle else None,
        "actual_selected_path": cycle["selected_path"] if cycle else None,
        "ok": ok,
    }


def probe_cycle_finish_rejects_decorated_status_marker() -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="upkeeper-lattice-cycle-finish-decorated-") as tmpdir:
        root = Path(tmpdir)
        selected_path = "tools/report-only.py"
        try:
            subprocess.run(["git", "init", "-q", str(root)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.CalledProcessError):
            pass
        (root / "tools").mkdir(parents=True, exist_ok=True)
        (root / "runtime").mkdir(parents=True, exist_ok=True)
        (root / selected_path).write_text("print('report only')\n", encoding="utf-8")
        review_path = root / "runtime" / "last-message.txt"
        review_path.write_text(
            "Selected file: `tools/report-only.py`\n"
            "`UPKEEPER_STATUS: WORK_DONE`\n"
            "REVIEWED_AND_REPORTED",
            encoding="utf-8",
        )
        db_path = root / "lattice.sqlite3"
        conn = connect_checked(root, db_path, "wal", allow_unsafe_db=True, create_parent=True, create_if_missing=True)
        try:
            init_schema(conn, root, raw_storage_mode="minimal")
        finally:
            conn.close()
        args = argparse.Namespace(
            root=str(root),
            db=str(db_path),
            journal_mode="wal",
            allow_unsafe_db=True,
            raw_storage_mode="minimal",
            cycle_id="cycle-decorated",
            run_hash="run-decorated",
            status_marker="WORK_DONE",
            review_outcome=None,
            review_selected_path=None,
            codex_exit=0,
            wrapper_exit=0,
            finish_reason="work_done",
            finish_level="info",
            codex_exec_started=1,
            dry_run="1",
            selected_path=selected_path,
            last_message_file=str(review_path),
            transcript_path=None,
            compiled_prompt_path=None,
            log_path=None,
            snapshot_kind="after_codex",
            end_epoch=1234567890,
        )
        with contextlib.redirect_stdout(io.StringIO()):
            command_record_cycle_finish(args)
        conn = connect_checked(root, db_path, "wal", allow_unsafe_db=True)
        try:
            cycle = conn.execute(
                """
                select status_marker, review_outcome, finish_reason, finish_level, selected_path
                  from cycles
                 where cycle_id=? and run_hash=?
                """,
                ("cycle-decorated", "run-decorated"),
            ).fetchone()
        finally:
            conn.close()
    return {
        "selected_path": selected_path,
        "status_marker": cycle["status_marker"] if cycle else None,
        "review_outcome": cycle["review_outcome"] if cycle else None,
        "finish_reason": cycle["finish_reason"] if cycle else None,
        "finish_level": cycle["finish_level"] if cycle else None,
        "actual_selected_path": cycle["selected_path"] if cycle else None,
        "ok": cycle is not None and cycle["status_marker"] is None,
    }


def probe_change_note_file_identity_validation() -> dict[str, Any]:
    results: dict[str, Any] = {}
    with tempfile.TemporaryDirectory(prefix="upkeeper-lattice-change-note-ref-") as repo_dir:
        root = Path(repo_dir).resolve()
        cases = {
            "valid_repo_file": ("tools/upkeeper_lattice.py", "tools/upkeeper_lattice.py"),
            "url_rejected": ("https://example.invalid/not-a-file.py", ""),
            "protocol_relative_rejected": ("//example.invalid/not-a-file.py", ""),
            "scheme_like_rejected": ("https:example.invalid/not-a-file.py", ""),
            "implicit_host_rejected": ("example.invalid/not-a-file.py", ""),
            "absolute_rejected": ("/tmp/not-a-file.py", ""),
            "traversal_rejected": ("../outside.py", ""),
            "control_char_rejected": ("docs/line\nbreak.py", ""),
            "runtime_rejected": ("runtime/generated/report.py", ""),
            "git_dir_rejected": (".git/hooks/pre-commit.py", ""),
            "upkeeper_log_rejected": ("Upkeeper.log", ""),
        }
        for name, (raw, expected) in cases.items():
            actual = normalize_repo_file_identity_ref(root, raw)
            results[name] = {
                "input": safe_output_text(raw),
                "expected": expected,
                "actual": actual,
                "ok": actual == expected,
            }
        with tempfile.TemporaryDirectory(prefix="upkeeper-lattice-change-note-outside-") as outside_dir:
            escape = root / "escape"
            try:
                os.symlink(outside_dir, escape, target_is_directory=True)
            except OSError as exc:
                results["symlink_escape_rejected"] = {
                    "supported": False,
                    "error": safe_output_text(str(exc)),
                    "ok": True,
                }
            else:
                actual = normalize_repo_file_identity_ref(root, "escape/not-a-file.py")
                results["symlink_escape_rejected"] = {
                    "supported": True,
                    "expected": "",
                    "actual": actual,
                    "ok": actual == "",
                }
    return results


def probe_candidate_symlink_exclusion() -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="upkeeper-lattice-symlink-candidate-") as repo_dir:
        root = Path(repo_dir).resolve()
        subprocess.run(["git", "init", "-q"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.email", "probe@example.com"], cwd=root, check=True)
        subprocess.run(["git", "config", "user.name", "Probe User"], cwd=root, check=True)
        target = root / "real.py"
        target.write_text("print('real')\n", encoding="utf-8")
        link = root / "linked.py"
        try:
            link.symlink_to(target.name)
        except OSError as exc:
            return {
                "supported": False,
                "error": safe_output_text(str(exc)),
                "ok": True,
            }
        subprocess.run(["git", "add", target.name, link.name], cwd=root, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "probe"], cwd=root, check=True)
        eligible_rows = {row["path"]: row for row in live_candidate_paths(root)}
        tracked_rows = {row["path"]: row for row in live_candidate_paths(root, candidate_scope="current-tracked")}
        link_meta = live_file_metadata(root, link.name)
        eligible_link = eligible_rows.get(link.name, {})
        tracked_link = tracked_rows.get(link.name, {})
        result = {
            "supported": True,
            "eligible_candidate_state": eligible_link.get("candidate_state"),
            "eligible_exclusion_reason": eligible_link.get("exclusion_reason"),
            "eligible_content_state": eligible_link.get("content_state"),
            "eligible_git_status": eligible_link.get("git_status"),
            "tracked_candidate_state": tracked_link.get("candidate_state"),
            "tracked_exclusion_reason": tracked_link.get("exclusion_reason"),
            "tracked_content_state": tracked_link.get("content_state"),
            "tracked_git_status": tracked_link.get("git_status"),
            "metadata_content_state": link_meta.get("content_state"),
            "metadata_git_status": link_meta.get("git_status"),
            "metadata_worktree_hash": link_meta.get("worktree_hash"),
            "metadata_head_blob": link_meta.get("head_blob"),
        }
        result["ok"] = all(
            (
                result["eligible_candidate_state"] == "excluded",
                result["eligible_exclusion_reason"] == "symlink",
                result["eligible_content_state"] == "symlink",
                result["eligible_git_status"] == "symlink",
                result["tracked_candidate_state"] == "excluded",
                result["tracked_exclusion_reason"] == "symlink",
                result["tracked_content_state"] == "symlink",
                result["tracked_git_status"] == "symlink",
                result["metadata_content_state"] == "symlink",
                result["metadata_git_status"] == "symlink",
                result["metadata_worktree_hash"] == "unavailable",
                result["metadata_head_blob"] == "none",
            )
        )
        return result


def probe_candidate_text_sample_limit() -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="upkeeper-lattice-text-sample-") as repo_dir:
        root = Path(repo_dir).resolve()
        candidate = root / "large.py"
        candidate.write_bytes(b"# probe\n" + (b"x" * (TEXT_SAMPLE_SIZE * 8)))
        read_sizes: list[int] = []
        original_read = read_fd_sample

        def recording_read(fd: int, size: int) -> bytes:
            read_sizes.append(size)
            return original_read(fd, size)

        try:
            globals()["read_fd_sample"] = recording_read
            rows = {row["path"]: row for row in live_candidate_paths(root)}
        finally:
            globals()["read_fd_sample"] = original_read
        row = rows.get(candidate.name, {})
        result = {
            "candidate_state": row.get("candidate_state"),
            "exclusion_reason": row.get("exclusion_reason"),
            "read_sizes": read_sizes,
            "max_read_size": max(read_sizes) if read_sizes else None,
        }
        result["ok"] = (
            result["candidate_state"] == "eligible"
            and result["exclusion_reason"] == ""
            and bool(read_sizes)
            and all(size == TEXT_SAMPLE_SIZE for size in read_sizes)
        )
        return result


def probe_export_redaction() -> dict[str, Any]:
    args = argparse.Namespace(
        redact_paths=True,
        redact_contributors=True,
        raw_export_policy="include",
    )
    selected_path = "tools/secret.py"
    local_remote = "file:///Users/alice/Secret Vault/upkeeper.git"
    payload = {
        "selected_path": selected_path,
        "remote_url": local_remote,
        "selectedPath": selected_path,
        "raw_text": f"selected_path={selected_path} selectedPath={selected_path} remote_url='{local_remote}' remoteURL='{local_remote}' email=alice@example.com",
        "details_json": json_dumps({"preselected_path": selected_path, "reported_selected_path": "docs/other.md"}),
        "parsed_json": json_dumps(
            {
                "selected_path": selected_path,
                "remote_url": local_remote,
                "nested": {"selected_path": selected_path},
                "review_selected_path": selected_path,
                "selection_map": {"review-selected-path": selected_path},
                "alias_value": selected_path,
                "aliases": [
                    {
                        "selected-file": selected_path,
                        "alias_value": selected_path,
                    }
                ],
                "report": {"selectedPath": selected_path, "remote_url": local_remote},
            }
        ),
    }
    redacted = redact_payload(payload, args)
    raw_text = str(redacted.get("raw_text") or "")
    return {
        "ok": (
            str(redacted.get("selected_path") or "").startswith(REDACTED_PATH_PREFIX)
            and str(redacted.get("remote_url") or "").startswith(REDACTED_PATH_PREFIX)
            and selected_path not in json_dumps(redacted)
            and local_remote not in json_dumps(redacted)
            and selected_path not in str(redacted.get("selectedPath") or "")
            and selected_path not in str(redacted.get("parsed_json") or "")
            and local_remote not in str(redacted.get("parsed_json") or "")
            and "alice@example.com" not in raw_text
            and "email=<redacted>" in raw_text
            and "selected_path=path-sha256:" in raw_text
            and "remote_url='path-sha256:" in raw_text
            and "selectedPath=path-sha256:" in raw_text
            and "remoteURL='path-sha256:" in raw_text
            and has_redacted_path_token(redacted)
        ),
        "raw_text": raw_text,
        "selected_path_redacted": str(redacted.get("selected_path") or "").startswith(REDACTED_PATH_PREFIX),
        "remote_url_redacted": str(redacted.get("remote_url") or "").startswith(REDACTED_PATH_PREFIX),
        "details_json_redacted": selected_path not in str(redacted.get("details_json") or ""),
        "parsed_json_redacted": local_remote not in str(redacted.get("parsed_json") or ""),
        "redacted_payload_detected": has_redacted_path_token(redacted),
    }


def snapshot_row_for_event(
    conn: sqlite3.Connection,
    *,
    repo_id: int,
    cycle_pk: int | None,
    file_id: int | None,
    event_kind: str,
) -> sqlite3.Row | None:
    if cycle_pk is None or file_id is None:
        return None
    row = conn.execute(
        """
        select details_json
          from file_events
         where repo_id=? and cycle_pk=? and file_id=? and event_kind=?
         order by event_epoch desc, event_id desc
         limit 1
        """,
        (repo_id, cycle_pk, file_id, event_kind),
    ).fetchone()
    if not row or not row["details_json"]:
        return None
    try:
        details = json.loads(row["details_json"])
    except json.JSONDecodeError:
        return None
    snapshot_id = details.get("snapshot_id")
    if not snapshot_id:
        return None
    return conn.execute(
        "select * from file_snapshots where snapshot_id=? and repo_id=?",
        (snapshot_id, repo_id),
    ).fetchone()


def has_clean_finish_evidence(
    conn: sqlite3.Connection,
    *,
    repo_id: int,
    cycle_pk: int | None,
    file_id: int | None,
    review_outcome: str | None,
) -> bool:
    if review_outcome == "REVIEWED_CLEAN":
        return True
    if cycle_pk is None or file_id is None:
        return False
    row = conn.execute(
        """
        select 1
          from file_pass_runs
         where repo_id=? and cycle_pk=? and file_id=?
           and outcome='clean'
           and coalesce(changed, 0)=0
           and coalesce(regression, 0)=0
         limit 1
        """,
        (repo_id, cycle_pk, file_id),
    ).fetchone()
    return row is not None


def record_selected_file_delta(
    conn: sqlite3.Connection,
    *,
    repo_id: int,
    cycle_pk: int | None,
    file_id: int | None,
    source_id: int | None,
    path: str,
    after_snapshot_id: int,
    review_outcome: str | None,
) -> None:
    before = snapshot_row_for_event(
        conn,
        repo_id=repo_id,
        cycle_pk=cycle_pk,
        file_id=file_id,
        event_kind="snapshot_before",
    )
    if not before and path:
        before = worktree_snapshot_path_row(
            conn,
            repo_id=repo_id,
            cycle_pk=cycle_pk,
            path=path,
            snapshot_kind="before_codex",
        )
    after = conn.execute(
        "select * from file_snapshots where snapshot_id=? and repo_id=?",
        (after_snapshot_id, repo_id),
    ).fetchone()
    if not before or not after:
        if has_clean_finish_evidence(conn, repo_id=repo_id, cycle_pk=cycle_pk, file_id=file_id, review_outcome=review_outcome):
            record_file_event(
                conn,
                repo_id,
                "clean_without_touch_evidence",
                file_id=file_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                path=path,
                details={"reason": "missing_before_or_after_snapshot", "after_snapshot_id": after_snapshot_id},
            )
        return

    before_hash = before["worktree_hash"]
    after_hash = after["worktree_hash"]
    before_mtime = before["mtime_epoch"]
    after_mtime = after["mtime_epoch"]
    before_mtime_ns = before["mtime_ns"]
    after_mtime_ns = after["mtime_ns"]
    details = {
        "before_snapshot_id": before["snapshot_id"] if "snapshot_id" in before.keys() else None,
        "before_worktree_snapshot_id": before["worktree_snapshot_id"] if "worktree_snapshot_id" in before.keys() else None,
        "after_snapshot_id": after["snapshot_id"],
        "before_worktree_hash": before_hash,
        "after_worktree_hash": after_hash,
        "before_mtime_epoch": before_mtime,
        "after_mtime_epoch": after_mtime,
        "before_mtime_ns": before_mtime_ns,
        "after_mtime_ns": after_mtime_ns,
    }

    if before_hash and after_hash and before_hash != after_hash:
        record_file_event(
            conn,
            repo_id,
            "changed",
            file_id=file_id,
            cycle_pk=cycle_pk,
            source_id=source_id,
            path=path,
            details=details,
        )
        return

    clean_evidence = has_clean_finish_evidence(
        conn,
        repo_id=repo_id,
        cycle_pk=cycle_pk,
        file_id=file_id,
        review_outcome=review_outcome,
    )
    if not clean_evidence:
        return
    if before_mtime is None or after_mtime is None:
        details["reason"] = "mtime_unavailable"
        record_file_event(
            conn,
            repo_id,
            "clean_without_touch_evidence",
            file_id=file_id,
            cycle_pk=cycle_pk,
            source_id=source_id,
            path=path,
            details=details,
        )
    elif before_mtime_ns is not None and after_mtime_ns is not None and int(before_mtime_ns) != int(after_mtime_ns):
        record_file_event(
            conn,
            repo_id,
            "touched_clean",
            file_id=file_id,
            cycle_pk=cycle_pk,
            source_id=source_id,
            path=path,
            details=details,
        )
    elif int(before_mtime) != int(after_mtime):
        record_file_event(
            conn,
            repo_id,
            "touched_clean",
            file_id=file_id,
            cycle_pk=cycle_pk,
            source_id=source_id,
            path=path,
            details=details,
        )


def create_artifact_ref(
    conn: sqlite3.Connection,
    root: Path,
    repo_id: int,
    *,
    cycle_pk: int | None,
    source_id: int | None,
    artifact_kind: str,
    path: str,
    expected_sha256: str | None = None,
    dedupe_identity: bool = False,
    details: Any = None,
) -> None:
    if not path:
        return
    p = canonical_artifact_path(root, path, artifact_kind)
    stored_path = artifact_storage_path(root, str(p))
    stored_details = artifact_details_payload(artifact_kind, details)
    expected_digest = normalize_hex_sha256(expected_sha256)
    try:
        entry = p.lstat()
    except OSError:
        entry = None
    if entry is not None and stat.S_ISLNK(entry.st_mode):
        fail(f"artifact path is a symlink and cannot be hashed: {p}", EXIT_USAGE)
    exists = entry is not None and stat.S_ISREG(entry.st_mode)
    if expected_digest is not None and not exists:
        fail(f"expected artifact missing for {artifact_kind}: {p}", EXIT_INTEGRITY)
    size = None
    digest = None
    digest_hmac = None
    if exists:
        try:
            if hasattr(os, "O_NOFOLLOW"):
                fd = os.open(str(p), os.O_RDONLY | os.O_NOFOLLOW)
            else:
                fd = os.open(str(p), os.O_RDONLY)
            try:
                hasher = hashlib.sha256()
                while True:
                    chunk = os.read(fd, 1024 * 1024)
                    if not chunk:
                        break
                    hasher.update(chunk)
                    size = (size or 0) + len(chunk)
                digest = hasher.hexdigest()
                digest_hmac = content_value_hmac(root, digest)
                if expected_digest is not None and digest != expected_digest:
                    fail(f"artifact hash mismatch for {artifact_kind}: {p}", EXIT_INTEGRITY)
            finally:
                os.close(fd)
        except OSError as exc:
            if expected_digest is not None:
                fail(f"artifact unreadable for {artifact_kind}: {p} ({exc})", EXIT_INTEGRITY)
            return
    stored_digest = digest_hmac or ""
    observed_epoch = epoch_now()
    if dedupe_identity:
        existing = conn.execute(
            """
            select artifact_id
            from artifact_refs
            where repo_id = ? and artifact_kind = ? and path = ? and coalesce(sha256, '') = coalesce(?, '')
            """,
            (repo_id, artifact_kind, stored_path, stored_digest),
        ).fetchone()
        if existing is not None:
            conn.execute(
                """
                update artifact_refs
                set
                  cycle_pk = coalesce(?, cycle_pk),
                  source_id = coalesce(?, source_id),
                  exists_at_record_time = ?,
                  size_bytes = ?,
                  observed_epoch = ?,
                  retained = ?,
                  details_json = coalesce(?, details_json)
                where artifact_id = ?
                """,
                (
                    cycle_pk,
                    source_id,
                    1 if exists else 0,
                    size,
                    observed_epoch,
                    1 if exists else 0,
                    json_dumps(stored_details),
                    existing["artifact_id"],
                ),
            )
            return

    try:
        conn.execute(
            """
            insert into artifact_refs(
              repo_id, cycle_pk, source_id, artifact_kind, path, exists_at_record_time,
              size_bytes, sha256, observed_epoch, retained, details_json
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                repo_id,
                cycle_pk,
                source_id,
                artifact_kind,
                stored_path,
                1 if exists else 0,
                size,
                stored_digest,
                observed_epoch,
                1 if exists else 0,
                json_dumps(stored_details),
            ),
        )
    except sqlite3.IntegrityError:
        if not dedupe_identity:
            raise
        conn.execute(
            """
            update artifact_refs
            set
              cycle_pk = coalesce(?, cycle_pk),
              source_id = coalesce(?, source_id),
              exists_at_record_time = ?,
              size_bytes = ?,
              observed_epoch = ?,
              retained = ?,
              details_json = coalesce(?, details_json)
            where repo_id = ? and artifact_kind = ? and path = ?
              and coalesce(sha256, '') = coalesce(?, '')
            """,
            (
                cycle_pk,
                source_id,
                1 if exists else 0,
                size,
                observed_epoch,
                1 if exists else 0,
                json_dumps(stored_details),
                repo_id,
                artifact_kind,
                stored_path,
                stored_digest,
            ),
        )


def command_record_cycle_finish(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    conn = connect_checked(root, normalize_db_path(args.db, root), args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    with conn:
        repo_id = ensure_repository(conn, root)
        parsed = vars(args).copy()
        parsed.pop("func", None)
        last_message_path = Path(args.last_message_file) if args.last_message_file else None
        review = parse_review_summary_file(last_message_path, root) if last_message_path else {}
        review_outcome = args.review_outcome or review.get("review_outcome") or None
        reported_selected = external_rel_path(args.review_selected_path or review.get("selected_file", ""))
        status_marker = parse_review_status_marker(last_message_path) if last_message_path else args.status_marker or ""
        finish_reason = args.finish_reason
        finish_level = args.finish_level
        source_id = ensure_source_record(
            conn,
            root,
            repo_id,
            "wrapper_observed",
            raw_ref="cycle_finish",
            parsed=parsed,
            raw_storage_mode=raw_storage_mode,
        )
        cycle_pk = ensure_cycle(conn, repo_id, args.cycle_id, args.run_hash, source_id=source_id)
        db_cycle = conn.execute(
            "select selected_file_id, selected_path from cycles where cycle_pk=?",
            (cycle_pk,),
        ).fetchone()
        db_selected_path = str(db_cycle["selected_path"] or "") if db_cycle else ""
        db_selected_file_id = db_cycle["selected_file_id"] if db_cycle else None
        selected_path = external_rel_path(args.selected_path or db_selected_path)
        selected_file_id = (
            ensure_file(conn, repo_id, selected_path, source_id=source_id)
            if selected_path
            else db_selected_file_id
        )
        cycle_selected_path = selected_path
        cycle_selected_file_id = int(selected_file_id) if selected_file_id is not None else None
        if reported_selected and not cycle_selected_path:
            # A reported target is not a safe substitute: without a preselected
            # target, we cannot safely re-anchor the cycle to a different file.
            record_file_event(
                conn,
                repo_id,
                "target_substitution_rejected",
                file_id=cycle_selected_file_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                path=cycle_selected_path or None,
                confidence="reported",
                details={"preselected_path": "", "reported_selected_path": reported_selected},
            )
            review_outcome = "STOPPED_ON_BLOCKER"
            status_marker = "BLOCKED"
            finish_reason = "selected_path_mismatch"
            finish_level = "error"
        elif reported_selected and cycle_selected_path and reported_selected != cycle_selected_path:
            # The wrapper-selected target is backed up before Codex runs, so a
            # different reported target is invalid evidence rather than a new cycle target.
            record_file_event(
                conn,
                repo_id,
                "target_substitution_rejected",
                file_id=cycle_selected_file_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                path=cycle_selected_path,
                confidence="reported",
                details={"preselected_path": selected_path, "reported_selected_path": reported_selected},
            )
            review_outcome = "STOPPED_ON_BLOCKER"
            status_marker = "BLOCKED"
            finish_reason = "selected_path_mismatch"
            finish_level = "error"
        updates: list[tuple[str, Any]] = [("end_epoch", args.end_epoch or epoch_now())]
        if status_marker:
            updates.append(("status_marker", status_marker))
        if review_outcome:
            updates.append(("review_outcome", review_outcome))
        if args.codex_exit is not None:
            updates.append(("codex_exit", args.codex_exit))
        if args.wrapper_exit is not None:
            updates.append(("wrapper_exit", args.wrapper_exit))
        if finish_reason:
            updates.append(("finish_reason", finish_reason))
        if finish_level:
            updates.append(("finish_level", finish_level))
        if args.codex_exec_started is not None:
            updates.append(("codex_exec_started", args.codex_exec_started))
        if args.dry_run is not None:
            updates.append(("dry_run", parse_bool_int(str(args.dry_run))))
        def parse_cycle_artifact_sha256(raw: Any, artifact_kind: str) -> str | None:
            if not has_meaningful_value(raw):
                return None
            digest = normalize_hex_sha256(raw)
            if digest is None:
                fail(f"invalid {artifact_kind} SHA-256 value: {raw}", EXIT_USAGE)
            return digest

        artifact_digests = {
            "transcript": parse_cycle_artifact_sha256(getattr(args, "transcript_sha256", None), "transcript"),
            "compiled_prompt": parse_cycle_artifact_sha256(
                getattr(args, "compiled_prompt_sha256", None), "compiled prompt"
            ),
            "last_message": parse_cycle_artifact_sha256(getattr(args, "last_message_sha256", None), "last message"),
            "upkeeper_log": parse_cycle_artifact_sha256(getattr(args, "log_sha256", None), "log"),
        }
        if cycle_selected_file_id is not None:
            updates.append(("selected_file_id", cycle_selected_file_id))
        if cycle_selected_path:
            updates.append(("selected_path", stored_rel_path(cycle_selected_path)))

        if updates:
            set_clause = ", ".join(f"{key}=?" for key, _ in updates)
            conn.execute(
                f"update cycles set {set_clause} where cycle_pk=?",
                [value for _, value in updates] + [cycle_pk],
            )
        snapshot_id = record_worktree_snapshot(conn, root, repo_id, cycle_pk, args.snapshot_kind, source_id=source_id)
        record_worktree_delta_events(
            conn,
            repo_id=repo_id,
            root=root,
            cycle_pk=cycle_pk,
            source_id=source_id,
            after_snapshot_id=snapshot_id,
        )
        if cycle_selected_path:
            after_snapshot_id = insert_file_snapshot(
                conn,
                root,
                repo_id,
                cycle_selected_path,
                file_id=cycle_selected_file_id,
                source_id=source_id,
            )
            record_file_event(
                conn,
                repo_id,
                "snapshot_after",
                file_id=cycle_selected_file_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                path=cycle_selected_path,
                details={"snapshot_id": after_snapshot_id},
            )
            record_selected_file_delta(
                conn,
                repo_id=repo_id,
                cycle_pk=cycle_pk,
                file_id=cycle_selected_file_id,
                source_id=source_id,
                path=cycle_selected_path,
                after_snapshot_id=after_snapshot_id,
                review_outcome=review_outcome,
            )
        for artifact_kind, artifact_path in [
            ("transcript", args.transcript_path),
            ("compiled_prompt", args.compiled_prompt_path),
            ("last_message", args.last_message_file),
            ("upkeeper_log", args.log_path),
        ]:
            create_artifact_ref(
                conn,
                root,
                repo_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                artifact_kind=artifact_kind,
                path=artifact_path or "",
                expected_sha256=artifact_digests[artifact_kind],
            )
    print_json({"status": "ok", "cycle_pk": cycle_pk, "worktree_snapshot_id": snapshot_id})
    return EXIT_SUCCESS


def pass_result_rejection_kind(reason: str) -> str:
    if reason.startswith("shell_parse:"):
        return "shell_parse"
    if reason.startswith("duplicate_key:"):
        return "duplicate_key"
    if reason.startswith("unexpected_key:"):
        return "unexpected_key"
    if reason == "missing_pass_or_file":
        return "missing_required"
    return reason


def maybe_normalize_pass_code(raw: Any) -> str:
    text = str(raw or "").strip()
    return normalize_pass_code(text) if re.fullmatch(r"P[0-9A-Za-z_.-]+", text) else ""


def sanitize_rejected_pass_result(
    root: Path,
    item: dict[str, Any],
    *,
    selected_path: str = "",
    preserve_raw: bool = False,
) -> dict[str, Any]:
    fields = item.get("fields", {})
    if not isinstance(fields, dict):
        fields = {}
    rejected_path = external_rel_path(str(fields.get("file", ""))) if fields.get("file") else ""
    payload: dict[str, Any] = {
        "line_number": int(item.get("line_number", 0) or 0),
        "rejection_kind": pass_result_rejection_kind(str(item.get("reason", "rejected"))),
    }
    normalized_pass = maybe_normalize_pass_code(fields.get("pass"))
    if normalized_pass:
        payload["pass"] = normalized_pass
    if rejected_path:
        payload["path_hmac"] = pass_result_path_hmac(root, rejected_path)
    if selected_path:
        payload["selected_path_hmac"] = pass_result_path_hmac(root, selected_path)
    if preserve_raw and item.get("reason"):
        payload["reason"] = str(item["reason"])
    return payload


def parse_pass_result_lines(path: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    accepted: list[dict[str, Any]] = []
    rejected: list[dict[str, Any]] = []
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return accepted, rejected
    in_fence = False
    for line_number, raw_line in enumerate(lines, start=1):
        stripped = raw_line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence or "UPKEEPER_PASS_RESULT:" not in stripped:
            continue
        if not stripped.startswith("UPKEEPER_PASS_RESULT:"):
            rejected.append({"raw_line": raw_line, "line_number": line_number, "reason": "decorated_marker"})
            continue
        payload = stripped.split(":", 1)[1].strip()
        try:
            tokens = shlex.split(payload)
        except ValueError as exc:
            rejected.append({"raw_line": raw_line, "line_number": line_number, "reason": f"shell_parse:{exc}"})
            continue
        fields: dict[str, str] = {}
        duplicate = ""
        malformed = False
        for token in tokens:
            if "=" not in token:
                malformed = True
                break
            key, value = token.split("=", 1)
            if key in fields:
                duplicate = key
                break
            fields[key] = value
        if malformed:
            rejected.append({"raw_line": raw_line, "line_number": line_number, "reason": "malformed_token", "fields": fields})
            continue
        if duplicate:
            rejected.append({"raw_line": raw_line, "line_number": line_number, "reason": f"duplicate_key:{duplicate}", "fields": fields})
            continue
        extras = sorted(key for key in fields if key not in PASS_RESULT_ALLOWED_KEYS)
        if extras:
            rejected.append(
                {
                    "raw_line": raw_line,
                    "line_number": line_number,
                    "reason": f"unexpected_key:{extras[0]}",
                    "fields": fields,
                }
            )
            continue
        if not fields.get("pass") or not fields.get("file"):
            rejected.append({"raw_line": raw_line, "line_number": line_number, "reason": "missing_pass_or_file", "fields": fields})
            continue
        if not re.fullmatch(r"P[0-9A-Za-z_.-]+", fields["pass"]):
            rejected.append({"raw_line": raw_line, "line_number": line_number, "reason": "invalid_pass", "fields": fields})
            continue
        outcome = fields.get("outcome", "unknown")
        if outcome not in ALLOWED_OUTCOMES:
            rejected.append({"raw_line": raw_line, "line_number": line_number, "reason": "invalid_outcome", "fields": fields})
            continue
        fields["raw_line"] = raw_line
        fields["line_number"] = str(line_number)
        accepted.append(fields)
    return accepted, rejected


def record_one_pass_result(
    conn: sqlite3.Connection,
    root: Path,
    repo_id: int,
    *,
    cycle_pk: int | None,
    source_id: int,
    pass_code: str,
    path: str,
    applicable: int | None,
    outcome: str,
    changed: int | None,
    regression: int | None,
    planned: int | None = None,
    raw_line: str = "",
    confidence: str = "reported",
    attributes: dict[str, Any] | None = None,
) -> int:
    pass_id = ensure_pass(conn, pass_code)
    file_id = ensure_file(conn, repo_id, path, source_id=source_id)
    attempted = 1 if outcome not in {"planned", "unknown"} else 0
    resolved_planned = 1 if (planned is not None and bool(planned)) or (planned is None and outcome == "planned") else 0
    cur = conn.execute(
        """
        insert into file_pass_runs(
          repo_id, file_id, cycle_pk, pass_id, pass_code, planned, applicable,
          attempted, outcome, changed, regression, confidence, source_id, raw_line, created_epoch
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            repo_id,
            file_id,
            cycle_pk,
            pass_id,
            normalize_pass_code(pass_code),
            resolved_planned,
            applicable,
            attempted,
            outcome,
            changed,
            regression,
            confidence,
            source_id,
            raw_line or None,
            epoch_now(),
        ),
    )
    run_id = int(cur.lastrowid)
    record_file_event(
        conn,
        repo_id,
        "pass_result" if outcome != "planned" else "pass_planned",
        file_id=file_id,
        cycle_pk=cycle_pk,
        source_id=source_id,
        path=path,
        confidence=confidence,
        details={"pass": pass_code, "outcome": outcome, "changed": changed, "regression": regression},
    )
    if changed:
        record_file_event(
            conn,
            repo_id,
            "changed",
            file_id=file_id,
            cycle_pk=cycle_pk,
            source_id=source_id,
            path=path,
            confidence=confidence,
            details={"pass": pass_code, "outcome": outcome, "source": "UPKEEPER_PASS_RESULT"},
        )
    if regression:
        conn.execute(
            """
            insert into regression_events(repo_id, file_id, cycle_pk, marked_epoch, confidence, detector, reason, status, source_id)
            values (?, ?, ?, ?, ?, ?, ?, 'active', ?)
            """,
            (
                repo_id,
                file_id,
                cycle_pk,
                epoch_now(),
                "asserted",
                "UPKEEPER_PASS_RESULT",
                f"{pass_code} reported regression=1 outcome={outcome}",
                source_id,
            ),
        )
        record_file_event(conn, repo_id, "regression_marked", file_id=file_id, cycle_pk=cycle_pk, source_id=source_id, path=path)
    for attr_key, attr_value in (attributes or {}).items():
        if ":" in attr_key:
            namespace, key = attr_key.split(":", 1)
        else:
            namespace, key = "upkeeper.pass_result", attr_key
        value_type = "text"
        value_text = str(attr_value)
        value_integer = None
        value_real = None
        value_json = None
        if isinstance(attr_value, bool):
            value_type = "integer"
            value_integer = 1 if attr_value else 0
            value_text = None
        elif isinstance(attr_value, int):
            value_type = "integer"
            value_integer = attr_value
            value_text = None
        elif isinstance(attr_value, float):
            value_type = "real"
            value_real = attr_value
            value_text = None
        elif isinstance(attr_value, (dict, list)):
            value_type = "json"
            value_json = json_dumps(attr_value)
            value_text = None
        conn.execute(
            """
            insert or ignore into pass_run_attributes(
              file_pass_run_id, namespace, key, value_type, value_text, value_integer,
              value_real, value_json, confidence, source_id, created_epoch
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                run_id,
                namespace,
                key,
                value_type,
                value_text,
                value_integer,
                value_real,
                value_json,
                confidence,
                source_id,
                epoch_now(),
            ),
        )
    return run_id


def command_record_pass_result(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    conn = connect_checked(root, normalize_db_path(args.db, root), args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    recorded = 0
    rejected_count = 0
    preserve_raw = pass_result_debug_storage_enabled(raw_storage_mode)
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(
            conn,
            root,
            repo_id,
            "transcript" if args.from_file else "wrapper_observed",
            source_path=args.from_file or "",
            raw_ref="pass_result",
            parsed=vars(args),
            raw_storage_mode=raw_storage_mode,
        )
        cycle_pk = None
        if args.cycle_id and args.run_hash:
            cycle_pk = ensure_cycle(conn, repo_id, args.cycle_id, args.run_hash, source_id=source_id)
        planned = split_csv(args.planned_passes)
        planned.extend(args.planned_pass or [])
        seen: set[tuple[str, str]] = set()
        rejected_pairs: set[tuple[str, str]] = set()
        trusted_selected_path = external_rel_path(args.selected_path or "")
        if args.from_file:
            accepted, rejected = parse_pass_result_lines(Path(args.from_file))
            for item in rejected:
                fields = item.get("fields", {})
                if isinstance(fields, dict):
                    rejected_pass = maybe_normalize_pass_code(fields.get("pass"))
                    rejected_path = trusted_selected_path or (
                        external_rel_path(str(fields.get("file", ""))) if fields.get("file") else ""
                    )
                    if rejected_pass and rejected_path:
                        rejected_pairs.add((rejected_pass, rejected_path))
                line_number = 0
                try:
                    line_number = int(item.get("line_number", 0) or 0)
                except (TypeError, ValueError):
                    line_number = 0
                raw_line = item.get("raw_line", "") if preserve_raw else ""
                ensure_source_record(
                    conn,
                    root,
                    repo_id,
                    "transcript",
                    source_path=args.from_file,
                    raw_ref=f"pass_result_rejected:{item.get('line_number')}",
                    raw_text=raw_line if preserve_raw else None,
                    parsed=sanitize_rejected_pass_result(
                        root,
                        item,
                        selected_path=trusted_selected_path,
                        preserve_raw=preserve_raw,
                    ),
                    parse_status="rejected",
                    fact_confidence="rejected",
                    source_line=line_number,
                    raw_sha256=sha256_text(raw_line) if preserve_raw else sha256_text(str(line_number)),
                    raw_storage_mode=raw_storage_mode,
                )
                rejected_count += 1
            for item in accepted:
                pass_code = normalize_pass_code(item["pass"])
                reported_path = external_rel_path(item["file"])
                outcome = item.get("outcome", "unknown")
                if trusted_selected_path and reported_path != trusted_selected_path:
                    rejected_pairs.add((pass_code, trusted_selected_path))
                    line_number = 0
                    try:
                        line_number = int(item.get("line_number", 0) or 0)
                    except (TypeError, ValueError):
                        line_number = 0
                    raw_line = item.get("raw_line", "") if preserve_raw else ""
                    ensure_source_record(
                        conn,
                        root,
                        repo_id,
                        "transcript",
                        source_path=args.from_file,
                        raw_ref=f"pass_result_rejected:{item.get('line_number')}",
                        raw_text=item.get("raw_line", "") if preserve_raw else None,
                        parsed={
                            "line_number": int(item.get("line_number", 0) or 0),
                            "pass": pass_code,
                            "rejection_kind": "selected_path_mismatch",
                            "path_hmac": pass_result_path_hmac(root, reported_path),
                            "selected_path_hmac": pass_result_path_hmac(root, trusted_selected_path),
                        },
                        parse_status="rejected",
                        fact_confidence="rejected",
                        source_line=line_number,
                        raw_sha256=sha256_text(raw_line) if preserve_raw else sha256_text(str(line_number)),
                        raw_storage_mode=raw_storage_mode,
                    )
                    rejected_count += 1
                    continue
                path = trusted_selected_path or reported_path
                try:
                    applicable = parse_pass_result_bool(item.get("applicable"), "applicable")
                    changed = parse_pass_result_bool(item.get("changed"), "changed")
                    regression = parse_pass_result_bool(item.get("regression"), "regression")
                except ValueError as exc:
                    rejection = sanitize_rejected_pass_result(
                        root,
                        {
                            "line_number": item.get("line_number", 0),
                            "reason": str(exc),
                            "fields": {
                                "pass": item.get("pass"),
                                "file": item.get("file"),
                                "outcome": outcome,
                                "applicable": item.get("applicable", ""),
                                "changed": item.get("changed", ""),
                                "regression": item.get("regression", ""),
                            },
                        },
                        selected_path=trusted_selected_path,
                        preserve_raw=preserve_raw,
                    )
                    rejection["validation_error"] = str(exc)
                    line_number = 0
                    try:
                        line_number = int(item.get("line_number", 0) or 0)
                    except (TypeError, ValueError):
                        line_number = 0
                    raw_line = item.get("raw_line", "") if preserve_raw else ""
                    ensure_source_record(
                        conn,
                        root,
                        repo_id,
                        "transcript",
                        source_path=args.from_file,
                        raw_ref=f"pass_result_rejected:{item.get('line_number')}",
                        raw_text=raw_line if preserve_raw else None,
                        parsed=rejection,
                        parse_status="rejected",
                        fact_confidence="rejected",
                        source_line=line_number,
                        raw_sha256=sha256_text(raw_line) if preserve_raw else sha256_text(str(line_number)),
                        raw_storage_mode=raw_storage_mode,
                    )
                    rejected_count += 1
                    continue
                validation_error = validate_pass_result_state(applicable=applicable, outcome=outcome)
                if validation_error:
                    rejection = sanitize_rejected_pass_result(
                        root,
                        {
                            "line_number": item.get("line_number", 0),
                            "reason": validation_error,
                            "fields": {
                                "pass": item.get("pass"),
                                "file": item.get("file"),
                                "outcome": outcome,
                                "applicable": item.get("applicable", ""),
                            },
                        },
                        selected_path=trusted_selected_path,
                        preserve_raw=preserve_raw,
                    )
                    rejection["validation_error"] = validation_error
                    line_number = 0
                    try:
                        line_number = int(item.get("line_number", 0) or 0)
                    except (TypeError, ValueError):
                        line_number = 0
                    ensure_source_record(
                        conn,
                        root,
                        repo_id,
                        "transcript",
                        source_path=args.from_file,
                        raw_ref=f"pass_result_rejected:{item.get('line_number')}",
                        raw_text=item.get("raw_line", "") if preserve_raw else None,
                        parsed=rejection,
                        parse_status="rejected",
                        fact_confidence="rejected",
                        source_line=line_number,
                        raw_storage_mode=raw_storage_mode,
                    )
                    rejected_count += 1
                    continue
                record_one_pass_result(
                    conn,
                    root,
                    repo_id,
                    cycle_pk=cycle_pk,
                    source_id=source_id,
                    pass_code=pass_code,
                    path=path,
                    applicable=applicable,
                    outcome=outcome,
                    changed=changed,
                    regression=regression,
                    raw_line=item.get("raw_line", "") if preserve_raw else "",
                    planned=0,
                    attributes={
                        "upkeeper.pass_result:path_hmac": pass_result_path_hmac(root, path),
                    },
                )
                seen.add((pass_code, path))
                recorded += 1
        elif args.pass_code and args.path:
            pass_code = normalize_pass_code(args.pass_code)
            path = external_rel_path(args.path)
            attrs = parse_attribute_args(args.attribute)
            try:
                applicable = parse_pass_result_bool(args.applicable, "--applicable")
                changed = parse_pass_result_bool(args.changed, "--changed")
                regression = parse_pass_result_bool(args.regression, "--regression")
            except ValueError as exc:
                fail(str(exc), EXIT_USAGE)
            outcome = args.outcome
            validation_error = validate_pass_result_state(applicable=applicable, outcome=outcome)
            if validation_error:
                fail(f"invalid pass-result state: {validation_error}", EXIT_USAGE)
            record_one_pass_result(
                conn,
                root,
                repo_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                pass_code=pass_code,
                path=path,
                applicable=applicable,
                outcome=outcome,
                changed=changed,
                regression=regression,
                raw_line=args.raw_line if preserve_raw else "",
                planned=0,
                attributes=attrs,
            )
            seen.add((pass_code, path))
            recorded += 1
        target_path = external_rel_path(args.path or args.selected_path or "")
        for raw_pass in planned:
            pass_code = normalize_pass_code(raw_pass)
            if not target_path or (pass_code, target_path) in seen:
                continue
            inferred_outcome = "unknown" if (pass_code, target_path) in rejected_pairs else "planned"
            record_one_pass_result(
                conn,
                root,
                repo_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                pass_code=pass_code,
                path=target_path,
                applicable=None,
                outcome=inferred_outcome,
                changed=None,
                regression=None,
                raw_line="",
                confidence="missing_marker",
                planned=1,
            )
            recorded += 1
        refresh_rollups(conn, repo_id)
    print_json({"status": "ok", "recorded": recorded, "rejected": rejected_count})
    return EXIT_SUCCESS


def split_csv(raw: str | None) -> list[str]:
    if not raw:
        return []
    return [item.strip() for item in raw.split(",") if item.strip()]


def parse_attribute_args(items: list[str] | None) -> dict[str, Any]:
    attrs: dict[str, Any] = {}
    for item in items or []:
        if "=" not in item:
            fail(f"--attribute requires namespace:key=value, got {item}", EXIT_USAGE)
        key, value = item.split("=", 1)
        if value.isdigit():
            attrs[key] = int(value)
        else:
            try:
                attrs[key] = json.loads(value)
            except json.JSONDecodeError:
                attrs[key] = value
    return attrs


def refresh_rollups(
    conn: sqlite3.Connection,
    repo_id: int,
    *,
    file_ids: Iterable[int] | None = None,
) -> None:
    now = epoch_now()
    if file_ids is None:
        file_ids = [int(row["file_id"]) for row in conn.execute("select file_id from files where repo_id=?", (repo_id,))]
    else:
        normalized_file_ids_set: set[int] = set()
        for file_id in file_ids:
            try:
                normalized_file_id = int(file_id)
            except (TypeError, ValueError):
                continue
            if normalized_file_id > 0:
                normalized_file_ids_set.add(normalized_file_id)
        normalized_file_ids = sorted(normalized_file_ids_set)
        if not normalized_file_ids:
            return
        placeholders = ",".join(["?"] * len(normalized_file_ids))
        file_ids = [
            int(row["file_id"])
            for row in conn.execute(
                f"select file_id from files where repo_id=? and file_id in ({placeholders})",
                (repo_id, *normalized_file_ids),
            )
        ]
    if not file_ids:
        return
    for file_id in file_ids:
        rows = [
            dict(row)
            for row in conn.execute(
                "select outcome, planned, applicable, attempted, changed, regression from file_pass_runs where repo_id=? and file_id=?",
                (repo_id, file_id),
            )
        ]
        counts = {
            "planned_count": sum(1 for r in rows if int(r.get("planned") or 0) == 1),
            "applicable_count": sum(1 for r in rows if int(r.get("applicable") or 0) == 1),
            "attempted_count": sum(1 for r in rows if int(r.get("attempted") or 0) == 1),
            "completed_count": sum(1 for r in rows if r.get("outcome") in COMPLETED_OUTCOMES),
            "blocked_count": sum(1 for r in rows if r.get("outcome") == "blocked"),
            "changed_count": sum(1 for r in rows if int(r.get("changed") or 0) == 1),
            "clean_count": sum(1 for r in rows if r.get("outcome") == "clean"),
            "not_applicable_count": sum(1 for r in rows if r.get("outcome") == "not_applicable"),
            "unknown_count": sum(1 for r in rows if r.get("outcome") == "unknown"),
            "regression_count": sum(1 for r in rows if int(r.get("regression") or 0) == 1 or r.get("outcome") == "regression_found"),
        }
        conn.execute(
            """
            insert into file_pass_rollups(
              file_id, planned_count, applicable_count, attempted_count, completed_count,
              blocked_count, changed_count, clean_count, not_applicable_count, unknown_count,
              regression_count, updated_epoch
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            on conflict(file_id) do update set
              planned_count=excluded.planned_count,
              applicable_count=excluded.applicable_count,
              attempted_count=excluded.attempted_count,
              completed_count=excluded.completed_count,
              blocked_count=excluded.blocked_count,
              changed_count=excluded.changed_count,
              clean_count=excluded.clean_count,
              not_applicable_count=excluded.not_applicable_count,
              unknown_count=excluded.unknown_count,
              regression_count=excluded.regression_count,
              updated_epoch=excluded.updated_epoch
            """,
            (
                file_id,
                counts["planned_count"],
                counts["applicable_count"],
                counts["attempted_count"],
                counts["completed_count"],
                counts["blocked_count"],
                counts["changed_count"],
                counts["clean_count"],
                counts["not_applicable_count"],
                counts["unknown_count"],
                counts["regression_count"],
                now,
            ),
        )


def ensure_contributor(
    conn: sqlite3.Connection,
    name: str,
    email: str,
    *,
    include_pii: bool = False,
) -> int | None:
    ensure_contributor_privacy_columns(conn)
    if not name and not email:
        return None
    identity_hash = contributor_identity_hash(name, email)
    row = conn.execute(
        "select contributor_id, identity_hash from contributors where identity_hash=?",
        (identity_hash,),
    ).fetchone()
    if not row:
        row = conn.execute(
            "select contributor_id, identity_hash from contributors where name is ? and email is ?",
            (name or None, email or None),
        ).fetchone()
    if row:
        contributor_id = int(row["contributor_id"])
        if include_pii:
            conn.execute(
                """
                update contributors
                set identity_hash=?, name=?, email=?, pii_included=1
                where contributor_id=?
                """,
                (identity_hash, name or None, email or None, contributor_id),
            )
        elif not row["identity_hash"]:
            conn.execute(
                """
                update contributors
                set identity_hash=?, name=NULL, email=NULL, github_login=NULL, pii_included=0
                where contributor_id=?
                """,
                (identity_hash, contributor_id),
            )
        return contributor_id
    cur = conn.execute(
        "insert into contributors(name, email, identity_hash, pii_included) values (?, ?, ?, ?)",
        (
            (name or None) if include_pii else None,
            (email or None) if include_pii else None,
            identity_hash,
            1 if include_pii else 0,
        ),
    )
    return int(cur.lastrowid)


def command_import_git(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    include_contributor_pii = bool(getattr(args, "include_contributor_pii", False))
    include_commit_subjects = bool(getattr(args, "include_commit_subjects", False))
    if not inside_git_repo(root):
        print_json({"status": "unavailable", "reason": "no_git_repository"})
        return EXIT_GIT_UNAVAILABLE
    conn = connect_checked(root, normalize_db_path(args.db, root), args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    rows_seen = 0
    commits_written = 0
    file_changes_seen = 0
    rows_written = 0
    duplicate_file_changes = 0
    with conn:
        scrub_legacy_git_privacy_data(conn)
        repo_id = ensure_repository(conn, root)
        import_id = start_import(conn, repo_id, "local_git", {"root": str(root)})
        source_id = ensure_source_record(
            conn,
            root,
            repo_id,
            "local_git",
            raw_ref="git-import",
            parse_status="started",
            raw_storage_mode=raw_storage_mode,
        )
        try:
            revs = subprocess.check_output(["git", "-C", str(root), "rev-list", "--all", "--reverse"], text=True)
        except subprocess.CalledProcessError:
            finish_import(conn, import_id, "unavailable", rows_seen, rows_written, 0, {"reason": "git_rev_list_failed"})
            print_json({"status": "unavailable", "reason": "git_rev_list_failed"})
            return EXIT_GIT_UNAVAILABLE
        shas = [line.strip() for line in revs.splitlines() if line.strip()]
        if args.limit:
            shas = shas[-int(args.limit) :]
        head_sha = git_output(root, ["rev-parse", "--verify", "HEAD"], "")
        for sha in shas:
            rows_seen += 1
            try:
                raw = subprocess.check_output(
                    [
                        "git",
                        "-C",
                        str(root),
                        "show",
                        "--no-ext-diff",
                        "--no-textconv",
                        "--format=%H%x00%an%x00%ae%x00%at%x00%cn%x00%ce%x00%ct%x00%s%x00",
                        "--name-status",
                        "--find-renames",
                        "-z",
                        sha,
                    ]
                )
            except subprocess.CalledProcessError:
                continue
            parts = decode_git_output(raw).split("\0")
            if len(parts) < 8:
                continue
            commit_sha, an, ae, at, cn, ce, ct, subject = parts[:8]
            commit_row = conn.execute(
                "select commit_id, source_id from git_commits where repo_id=? and sha=?",
                (repo_id, commit_sha),
            ).fetchone()
            if commit_row:
                commit_id = int(commit_row["commit_id"])
                commit_source_id = int(commit_row["source_id"]) if commit_row["source_id"] is not None else None
            else:
                author_id = ensure_contributor(conn, an, ae, include_pii=include_contributor_pii)
                committer_id = ensure_contributor(conn, cn, ce, include_pii=include_contributor_pii)
                subject_summary = commit_subject_summary(
                    subject if include_commit_subjects else None,
                    commit_subject_hash(subject),
                    len(subject),
                    1 if include_commit_subjects else 0,
                )
                commit_source_id = ensure_source_record(
                    conn,
                    root,
                    repo_id,
                    "local_git",
                    raw_ref=commit_sha,
                    parsed=local_git_source_payload(
                        contributor_identity_hash(an, ae) or None,
                        contributor_identity_hash(cn, ce) or None,
                        subject,
                        include_commit_subjects=include_commit_subjects,
                    ),
                    source_epoch=int(at or 0) if str(at).isdigit() else None,
                    parse_status="parsed",
                    raw_storage_mode=raw_storage_mode,
                )
                cur = conn.execute(
                    """
                    insert into git_commits(
                      repo_id, sha, author_id, committer_id, author_epoch, committer_epoch,
                      subject, subject_hash, subject_length, subject_included, source_id
                    ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        repo_id,
                        commit_sha,
                        author_id,
                        committer_id,
                        int(at or 0) if str(at).isdigit() else None,
                        int(ct or 0) if str(ct).isdigit() else None,
                        subject_summary["subject"],
                        subject_summary["subject_hash"],
                        subject_summary["subject_length"],
                        subject_summary["subject_included"],
                        commit_source_id,
                    ),
                )
                commit_id = int(cur.lastrowid)
                commits_written += 1
            if commit_row:
                subject_summary = commit_subject_summary(
                    subject if include_commit_subjects else None,
                    commit_subject_hash(subject),
                    len(subject),
                    1 if include_commit_subjects else 0,
                )
                author_id = ensure_contributor(conn, an, ae, include_pii=include_contributor_pii)
                committer_id = ensure_contributor(conn, cn, ce, include_pii=include_contributor_pii)
                conn.execute(
                    """
                    update git_commits
                    set author_id=coalesce(author_id, ?),
                        committer_id=coalesce(committer_id, ?),
                        subject_hash=coalesce(subject_hash, ?),
                        subject_length=coalesce(subject_length, ?),
                        subject_included=case
                          when ?=1 then 1
                          else coalesce(subject_included, 0)
                        end,
                        subject=case
                          when ?=1 then ?
                          when coalesce(subject_included, 0)=1 then subject
                          else NULL
                        end
                    where commit_id=?
                    """,
                    (
                        author_id,
                        committer_id,
                        subject_summary["subject_hash"],
                        subject_summary["subject_length"],
                        subject_summary["subject_included"],
                        subject_summary["subject_included"],
                        subject_summary["subject"],
                        commit_id,
                    ),
                )
                if commit_source_id is not None:
                    normalized_commit_source = normalize_source_record_parsed(
                        "local_git",
                        commit_sha,
                        "parsed",
                        local_git_source_payload(
                            contributor_identity_hash(an, ae) or None,
                            contributor_identity_hash(cn, ce) or None,
                            subject,
                            include_commit_subjects=include_commit_subjects,
                        ),
                        raw_storage_mode=raw_storage_mode,
                    )
                    conn.execute(
                        "update source_records set parsed_json=? where source_id=?",
                        (
                            json_dumps(normalized_commit_source) if normalized_commit_source is not None else None,
                            commit_source_id,
                        ),
                    )
            i = 8
            while i < len(parts):
                status_code = parts[i].strip()
                i += 1
                if not status_code:
                    continue
                if i >= len(parts):
                    break
                old_path = None
                path = parts[i]
                i += 1
                if not path:
                    continue
                if status_code.startswith(("R", "C")):
                    old_path = path
                    if i >= len(parts):
                        break
                    path = parts[i]
                    i += 1
                    if not path:
                        continue
                canonical = old_path if status_code.startswith("R") and old_path else path
                stored_path = stored_rel_path(path)
                stored_old_path = stored_rel_path(old_path) if old_path else None
                state = "deleted" if status_code.startswith("D") else ("renamed" if status_code.startswith("R") else "active")
                if sha == head_sha:
                    file_id = ensure_file(
                        conn,
                        repo_id,
                        path,
                        canonical_path=canonical,
                        state=state,
                        source_id=commit_source_id,
                        prefer_historical_match=True,
                    )
                else:
                    file_id = ensure_file_historical_only(
                        conn,
                        repo_id,
                        path,
                        canonical_path=canonical,
                        source_id=commit_source_id,
                    )
                if status_code.startswith("R") and old_path:
                    current_row = conn.execute(
                        """
                        select file_id
                        from files
                        where repo_id=? and current_path=?
                        order by case when canonical_path <> ? then 0 else 1 end, file_id
                        limit 1
                        """,
                        (repo_id, stored_path, stored_path),
                    ).fetchone()
                    if current_row:
                        current_file_id = int(current_row["file_id"])
                        if current_file_id != file_id:
                            file_id = merge_file_lineage(conn, file_id, current_file_id)
                file_changes_seen += 1
                cur = conn.execute(
                    """
                    insert or ignore into git_file_changes(
                      repo_id, commit_id, file_id, status, path, old_path, additions, deletions, change_epoch, source_id
                    ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        repo_id,
                        commit_id,
                        file_id,
                        status_code,
                        stored_path,
                        stored_old_path,
                        None,
                        None,
                        int(at or 0) if str(at).isdigit() else None,
                        commit_source_id,
                    ),
                )
                if cur.rowcount:
                    rows_written += 1
                else:
                    duplicate_file_changes += 1
                    conn.execute(
                        """
                        update git_file_changes
                        set file_id=?,
                            additions=coalesce(additions, ?),
                            deletions=coalesce(deletions, ?),
                            change_epoch=coalesce(change_epoch, ?),
                            source_id=coalesce(source_id, ?)
                        where repo_id=?
                          and commit_id=?
                          and path=?
                          and coalesce(old_path, '')=?
                          and coalesce(status, '')=?
                        """,
                        (
                            file_id,
                            None,
                            None,
                            int(at or 0) if str(at).isdigit() else None,
                            commit_source_id,
                            repo_id,
                            commit_id,
                            stored_path,
                            stored_old_path or "",
                            status_code,
                        ),
                    )
        sync_file_current_state_to_head(conn, root, repo_id, source_id=source_id)
        shallow = git_output(root, ["rev-parse", "--is-shallow-repository"], "false") == "true"
        conn.execute(
            """
            insert into import_cursors(repo_id, import_kind, scope, cursor_value, cursor_epoch, history_complete, incomplete_reason, source_id)
            values (?, 'local_git', 'rev-list --all --reverse', ?, ?, ?, ?, ?)
            on conflict(repo_id, import_kind, scope) do update set
              cursor_value=excluded.cursor_value,
              cursor_epoch=excluded.cursor_epoch,
              history_complete=excluded.history_complete,
              incomplete_reason=excluded.incomplete_reason,
              source_id=excluded.source_id
            """,
            (repo_id, shas[-1] if shas else "", epoch_now(), 0 if shallow else 1, "shallow_repository" if shallow else None, source_id),
        )
        finish_import(
            conn,
            import_id,
            "ok",
            rows_seen,
            rows_written,
            0,
            {
                "shallow": shallow,
                "commits_written": commits_written,
                "file_changes_seen": file_changes_seen,
                "file_changes_duplicate": duplicate_file_changes,
            },
        )
    print_json(
        {
            "status": "ok",
            "commits_seen": rows_seen,
            "commits_written": commits_written,
            "file_changes_seen": file_changes_seen,
            "file_changes_written": rows_written,
            "file_changes_duplicate": duplicate_file_changes,
        }
    )
    return EXIT_SUCCESS


def start_import(
    conn: sqlite3.Connection,
    repo_id: int,
    import_kind: str,
    details: Any = None,
    *,
    forced_id: int | None = None,
) -> int:
    if forced_id is None:
        cur = conn.execute(
            """
            insert into lattice_imports(repo_id, import_kind, started_epoch, status, rows_seen, rows_written, conflicts, details_json)
            values (?, ?, ?, 'started', 0, 0, 0, ?)
            """,
            (repo_id, import_kind, epoch_now(), json_dumps(details) if details is not None else None),
        )
    else:
        cur = conn.execute(
            """
            insert into lattice_imports(import_id, repo_id, import_kind, started_epoch, status, rows_seen, rows_written, conflicts, details_json)
            values (?, ?, ?, ?, 'started', 0, 0, 0, ?)
            """,
            (forced_id, repo_id, import_kind, epoch_now(), json_dumps(details) if details is not None else None),
        )
    return int(cur.lastrowid)


def finish_import(
    conn: sqlite3.Connection,
    import_id: int,
    status: str,
    rows_seen: int,
    rows_written: int,
    conflicts: int,
    details: Any = None,
) -> None:
    conn.execute(
        """
        update lattice_imports
        set finished_epoch=?, status=?, rows_seen=?, rows_written=?, conflicts=?, details_json=coalesce(?, details_json)
        where import_id=?
        """,
        (epoch_now(), status, rows_seen, rows_written, conflicts, json_dumps(details) if details is not None else None, import_id),
    )


def parse_upkeeper_log_line(line: str) -> dict[str, Any] | None:
    match = re.match(r"^(?P<timestamp>\S+)\s+\[(?P<level>[A-Z]+)\]\s+(?P<body>.*)$", line)
    if not match:
        return None
    body = match.group("body")
    try:
        parts = shlex.split(body)
    except ValueError:
        parts = body.split()
    if len(parts) < 3:
        return None
    parsed: dict[str, Any] = {"timestamp": match.group("timestamp"), "level": match.group("level"), "event": ""}
    for token in parts:
        if "=" in token:
            key, value = token.split("=", 1)
            parsed[key] = value
        elif not parsed["event"]:
            parsed["event"] = token
    return parsed


def filter_upkeeper_log_fields(parsed: dict[str, Any], allowed_keys: set[str]) -> dict[str, Any]:
    # Imported log storage should default to a small operational allowlist so
    # paths, targets, reasons, and other free-form detail do not survive as
    # structured records when raw line import is disabled.
    return {key: parsed[key] for key in allowed_keys if key in parsed}


def command_import_upkeeper_log(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    log_path = Path(args.path or root / "Upkeeper.log")
    conn = connect_checked(root, normalize_db_path(args.db, root), args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    rows_seen = rows_written = 0
    with conn:
        repo_id = ensure_repository(conn, root)
        import_id = start_import(conn, repo_id, "upkeeper_log", {"path": str(log_path)})
        if not log_path.exists():
            finish_import(conn, import_id, "unavailable", 0, 0, 0, {"reason": "missing_log"})
            print_json({"status": "unavailable", "reason": "missing_log", "path": str(log_path)})
            return EXIT_SUCCESS
        for line_number, raw_line in enumerate(log_path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
            rows_seen += 1
            parsed = parse_upkeeper_log_line(raw_line)
            if not parsed:
                continue
            safe_parsed = sanitize_upkeeper_log_parsed(parsed)
            stored_raw_line = raw_line if args.raw else None
            if stored_raw_line is not None:
                stored_raw_line = sanitize_upkeeper_log_raw_text(root, stored_raw_line, parsed)
            source_id = ensure_source_record(
                conn,
                root,
                repo_id,
                "upkeeper_log",
                source_path=str(log_path),
                raw_ref=parsed.get("event", ""),
                raw_text=stored_raw_line,
                parsed=safe_parsed,
                parse_status="parsed",
                source_line=line_number,
                raw_sha256=sha256_text(stored_raw_line) if stored_raw_line is not None else None,
                raw_storage_mode=raw_storage_mode,
            )
            cycle_id = str(parsed.get("cycle", ""))
            run_hash = str(parsed.get("run_hash", ""))
            event = str(parsed.get("event", ""))
            if cycle_id and run_hash:
                cycle_pk = ensure_cycle(conn, repo_id, cycle_id, run_hash, source_id=source_id)
                if event == "cycle.start":
                    start_fields = filter_upkeeper_log_fields(parsed, UPKEEPER_LOG_CYCLE_START_SAFE_KEYS)
                    dry_run = parse_bool_int(start_fields["dry_run"]) if "dry_run" in start_fields else None
                    worktree_dirty = parse_optional_dirty_paths(start_fields.get("dirty_paths")) if "dirty_paths" in start_fields else None
                    ensure_cycle(
                        conn,
                        repo_id,
                        cycle_id,
                        run_hash,
                        source_id=source_id,
                        execution_origin=start_fields.get("execution_origin"),
                        worktree_dirty=worktree_dirty,
                        dry_run=dry_run,
                    )
                elif event == "review.preselect":
                    preselect_fields = filter_upkeeper_log_fields(parsed, UPKEEPER_LOG_REVIEW_PRESELECT_SAFE_KEYS)
                    if str(preselect_fields.get("basis", "")).strip() != "":
                        conn.execute(
                            "update cycles set selection_basis=? where cycle_pk=?",
                            (preselect_fields.get("basis"), cycle_pk),
                        )
                elif event == "cycle.summary":
                    summary_fields = filter_upkeeper_log_fields(parsed, UPKEEPER_LOG_SUMMARY_SAFE_KEYS)
                    updates: dict[str, Any] = {}
                    if "status_marker" in summary_fields and str(summary_fields.get("status_marker", "")).strip() != "":
                        updates["status_marker"] = summary_fields.get("status_marker")
                    if "codex_exit" in summary_fields and str(summary_fields.get("codex_exit", "")).lstrip("-").isdigit():
                        updates["codex_exit"] = int(summary_fields["codex_exit"])
                    if updates:
                        conn.execute(
                            f"update cycles set {', '.join(f'{key}=?' for key in updates)} where cycle_pk=?",
                            list(updates.values()) + [cycle_pk],
                        )
                elif event == "cycle.exit":
                    exit_fields = filter_upkeeper_log_fields(parsed, UPKEEPER_LOG_EXIT_SAFE_KEYS)
                    updates: dict[str, Any] = {}
                    if "exit_code" in exit_fields and str(exit_fields.get("exit_code", "")).lstrip("-").isdigit():
                        updates["wrapper_exit"] = int(exit_fields["exit_code"])
                    if "codex_exec_started" in exit_fields and str(exit_fields.get("codex_exec_started", "")).strip() != "":
                        updates["codex_exec_started"] = parse_bool_int(str(exit_fields.get("codex_exec_started")))
                    if updates:
                        conn.execute(
                            f"update cycles set {', '.join(f'{key}=?' for key in updates)} where cycle_pk=?",
                            list(updates.values()) + [cycle_pk],
                        )
            rows_written += 1
        finish_import(conn, import_id, "ok", rows_seen, rows_written, 0, {"path": str(log_path)})
    print_json({"status": "ok", "rows_seen": rows_seen, "rows_written": rows_written})
    return EXIT_SUCCESS


def command_import_change_notes(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    paths = [Path(p) for p in args.paths] if args.paths else sorted(root.glob("change_notes_*.md"))
    conn = connect_checked(root, normalize_db_path(args.db, root), args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    rows_seen = rows_written = 0
    with conn:
        repo_id = ensure_repository(conn, root)
        import_id = start_import(conn, repo_id, "change_notes", {"paths": [str(p) for p in paths]})
        for path in paths:
            if not path.exists():
                continue
            current_date = ""
            current_version = ""
            for line_number, raw in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
                header = re.match(r"^([0-9]{4}-[0-9]{2}-[0-9]{2}):\s+([^:]+?)\s+changes:", raw)
                if header:
                    current_date, current_version = header.group(1), header.group(2).strip()
                    continue
                item = re.match(r"^\s*([0-9]+)[.)]\s+(.*\S)\s*$", raw)
                if not item or not current_date:
                    continue
                rows_seen += 1
                text = item.group(2)
                source_id = ensure_source_record(
                    conn,
                    root,
                    repo_id,
                    "change_notes",
                    source_path=str(path),
                    raw_ref=f"{current_version}:{line_number}",
                    raw_text=raw if args.raw else None,
                    parsed={"version": current_version, "date": current_date, "item_number": int(item.group(1)), "text": text},
                    source_line=line_number,
                    raw_sha256=sha256_text(raw),
                    raw_storage_mode=raw_storage_mode,
                )
                cur = conn.execute(
                    """
                    insert into change_log_entries(repo_id, version, entry_date, item_number, source_path, source_line, text, source_id)
                    values (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (repo_id, current_version, current_date, int(item.group(1)), str(path), line_number, text, source_id),
                )
                entry_id = int(cur.lastrowid)
                for ref in re.findall(r"`([^`]+\.[A-Za-z0-9]+)`", text):
                    normalized_ref = normalize_repo_file_identity_ref(root, ref)
                    if not normalized_ref:
                        continue
                    if "/" not in normalized_ref and normalized_ref not in {"Upkeeper", "README.md", "AGENTS.md"}:
                        continue
                    try:
                        file_id = ensure_file(conn, repo_id, normalized_ref, source_id=source_id)
                    except ValueError:
                        continue
                    conn.execute(
                        """
                        insert into change_log_file_refs(change_log_entry_id, file_id, path, confidence, source_id)
                        values (?, ?, ?, 'explicit_path', ?)
                        """,
                        (entry_id, file_id, ref, source_id),
                    )
                rows_written += 1
        finish_import(conn, import_id, "ok", rows_seen, rows_written, 0)
    print_json({"status": "ok", "rows_seen": rows_seen, "rows_written": rows_written})
    return EXIT_SUCCESS


def export_table_rows(
    conn: sqlite3.Connection,
    table: str,
    repo_id: int | None = None,
) -> Iterable[dict[str, Any]]:
    columns = table_columns(conn, table)
    if not columns:
        return []
    pk = table_primary_key(conn, table)
    order = pk or columns[0]
    if repo_id is None:
        return (dict(row) for row in conn.execute(f"select * from {table} order by {order}"))
    if "repo_id" in columns:
        return (dict(row) for row in conn.execute(f"select * from {table} where repo_id=? order by {order}", (repo_id,)))
    # Repo-scoped exports must prove ownership for tables that do not carry
    # repo_id directly; otherwise a shared DB can silently leak foreign rows.
    if table == "file_paths":
        query = """
            select file_paths.*
            from file_paths
            join files on files.file_id=file_paths.file_id
            where files.repo_id=?
            order by file_paths.file_path_id
        """
        return (dict(row) for row in conn.execute(query, (repo_id,)))
    if table == "worktree_snapshot_paths":
        query = """
            select worktree_snapshot_paths.*
            from worktree_snapshot_paths
            join worktree_snapshots on worktree_snapshots.worktree_snapshot_id=worktree_snapshot_paths.worktree_snapshot_id
            where worktree_snapshots.repo_id=?
            order by worktree_snapshot_paths.worktree_snapshot_path_id
        """
        return (dict(row) for row in conn.execute(query, (repo_id,)))
    if table == "selection_candidates":
        query = """
            select selection_candidates.*
            from selection_candidates
            join selection_runs on selection_runs.selection_run_id=selection_candidates.selection_run_id
            where selection_runs.repo_id=?
            order by selection_candidates.selection_candidate_id
        """
        return (dict(row) for row in conn.execute(query, (repo_id,)))
    if table == "review_passes":
        query = """
            select review_passes.*
            from review_passes
            where exists(
                select 1
                from file_pass_runs
                where file_pass_runs.repo_id=?
                  and file_pass_runs.pass_id=review_passes.pass_id
            )
            order by review_passes.pass_id
        """
        return (dict(row) for row in conn.execute(query, (repo_id,)))
    if table == "pass_run_attributes":
        query = """
            select pass_run_attributes.*
            from pass_run_attributes
            join file_pass_runs on file_pass_runs.file_pass_run_id=pass_run_attributes.file_pass_run_id
            where file_pass_runs.repo_id=?
            order by pass_run_attributes.attribute_id
        """
        return (dict(row) for row in conn.execute(query, (repo_id,)))
    if table == "contributors":
        query = """
            select contributors.*
            from contributors
            where exists(
                select 1
                from git_commits
                where git_commits.repo_id=?
                  and (
                      git_commits.author_id=contributors.contributor_id
                      or git_commits.committer_id=contributors.contributor_id
                  )
            )
            order by contributors.contributor_id
        """
        return (dict(row) for row in conn.execute(query, (repo_id,)))
    if table == "regression_causes":
        query = """
            select regression_causes.*
            from regression_causes
            join regression_events on regression_events.regression_id=regression_causes.regression_id
            where regression_events.repo_id=?
            order by regression_causes.regression_cause_id
        """
        return (dict(row) for row in conn.execute(query, (repo_id,)))
    if table == "change_log_file_refs":
        query = """
            select change_log_file_refs.*
            from change_log_file_refs
            join change_log_entries on change_log_entries.change_log_entry_id=change_log_file_refs.change_log_entry_id
            where change_log_entries.repo_id=?
            order by change_log_file_refs.change_log_file_ref_id
        """
        return (dict(row) for row in conn.execute(query, (repo_id,)))
    if table == "extension_namespaces":
        query = """
            select extension_namespaces.*
            from extension_namespaces
            where exists(
                select 1
                from extension_facts
                where extension_facts.repo_id=?
                  and extension_facts.namespace=extension_namespaces.namespace
            )
            order by extension_namespaces.namespace
        """
        return (dict(row) for row in conn.execute(query, (repo_id,)))
    if table == "extension_fact_types":
        query = """
            select extension_fact_types.*
            from extension_fact_types
            where exists(
                select 1
                from extension_facts
                where extension_facts.repo_id=?
                  and extension_facts.namespace=extension_fact_types.namespace
                  and extension_facts.key=extension_fact_types.key
                  and extension_facts.subject_type=extension_fact_types.subject_type
            )
            order by extension_fact_types.fact_type_id
        """
        return (dict(row) for row in conn.execute(query, (repo_id,)))
    if table in {
        "file_pass_rollups",
        "file_fragility_rollups",
        "file_git_churn_rollups",
        "file_selection_rollups",
        "file_failure_rollups",
    }:
        query = f"""
            select {table}.*
            from {table}
            join files on files.file_id={table}.file_id
            where files.repo_id=?
            order by {table}.file_id
        """
        return (dict(row) for row in conn.execute(query, (repo_id,)))
    if table in {"schema_meta", "schema_migrations"}:
        return (dict(row) for row in conn.execute(f"select * from {table} order by {order}"))
    fail(f"export-jsonl repo scope is undefined for table {table}", EXIT_INTEGRITY)


def redact_payload(payload: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return payload

    raw_export_policy = getattr(args, "raw_export_policy", "full_redact")

    def _redact(raw: Any, current_key: str | None = None) -> Any:
        if isinstance(raw, dict):
            out: dict[str, Any] = {}
            for key, value in raw.items():
                if key in STRUCTURED_REDACTION_STRING_KEYS and raw_export_policy != "include":
                    if raw_export_policy != "structured_redact":
                        out[key] = "<redacted>"
                        continue
                    if isinstance(value, str):
                        if looks_like_json_container_string(value):
                            try:
                                parsed = json.loads(value)
                            except (TypeError, json.JSONDecodeError):
                                parsed = None
                        else:
                            parsed = None
                        if isinstance(parsed, (dict, list)):
                            out[key] = json_dumps(_redact(parsed, key))
                        else:
                            out[key] = "<redacted>"
                    else:
                        out[key] = "<redacted>"
                    continue
                out[key] = _redact(value, key)
            return out
        if isinstance(raw, list):
            return [_redact(item, current_key) for item in raw]
        if isinstance(raw, str):
            if args.redact_paths and key_requires_path_redaction(current_key):
                return REDACTED_PATH_PREFIX + sha256_text(raw)
            if args.redact_contributors and current_key in CONTRIBUTOR_REDACT_KEYS:
                return "<redacted>"
            if (args.redact_paths or args.redact_contributors) and looks_like_json_container_string(raw):
                try:
                    parsed = json.loads(raw)
                except (TypeError, json.JSONDecodeError):
                    return raw
                if isinstance(parsed, (dict, list)):
                    redacted = _redact(parsed, current_key)
                    return json_dumps(redacted) if redacted != parsed else raw
            inline_redacted = redact_inline_assignment_string(
                raw,
                redact_paths=bool(args.redact_paths),
                redact_contributors=bool(args.redact_contributors),
            )
            if inline_redacted != raw:
                return inline_redacted
        return raw

    return _redact(payload)


def warn_sensitive_export_request(args: argparse.Namespace, output: Path) -> None:
    if getattr(args, "raw_export_policy", "full_redact") != "include":
        return
    print(
        "upkeeper_lattice: WARNING: export-jsonl requested --include-raw; "
        f"{output} remains mode 0600 but may contain sensitive local evidence",
        file=sys.stderr,
    )


def reject_nonfinite_json_constant(token: str) -> None:
    raise ValueError(f"unsupported non-finite JSON constant: {token}")


def load_strict_json(raw: str) -> Any:
    return json.loads(raw, parse_constant=reject_nonfinite_json_constant)


def sanitize_import_identity_payload(table: str, payload: dict[str, Any], context: tuple[str, str, str]) -> dict[str, Any]:
    if table == "repositories":
        return sanitize_repository_payload(payload, context)
    if table == "repo_aliases":
        return sanitize_repo_alias_payload(payload, context)
    if table in {"cycles", "worktree_snapshots"}:
        updated = dict(payload)
        branch_name = updated.get("branch_name")
        if isinstance(branch_name, str):
            updated["branch_name"] = protected_branch_name(context, branch_name)
        return updated
    return payload


def semantic_import_payload(table: str, payload: dict[str, Any]) -> dict[str, Any]:
    normalized = dict(payload)
    for key in ("source_id", "imported_epoch", "last_seen_epoch", "updated_epoch"):
        if key in normalized:
            normalized[key] = None
    if table == "schema_meta" and normalized.get("key") == "updated_epoch":
        normalized["value"] = None
    if table == "schema_migrations":
        normalized["applied_epoch"] = None
    return normalized


def align_redacted_import_compare_payload(incoming: dict[str, Any], existing: dict[str, Any]) -> dict[str, Any]:
    aligned = dict(incoming)
    for key, value in list(aligned.items()):
        if value == "<redacted>" and key in existing:
            aligned[key] = existing[key]
    return aligned


def command_export_jsonl(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    db_path = normalize_db_path(args.db, root)
    conn = connect_checked(root, db_path, args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    repo_id = ensure_repository(conn, root)
    context = repo_identity_context(root)
    output = validate_lattice_output_path(
        root,
        args.output if args.output else db_path.parent / "exports" / f"lattice-export-{epoch_now()}.jsonl",
        allow_existing=args.overwrite,
        journal_mode=args.journal_mode,
        db_path=db_path,
        allow_outside_runtime=args.output is not None,
    )
    if not output.parent.exists():
        output.parent.mkdir(parents=True, exist_ok=True)
        chmod_private(output.parent, is_dir=True, created_by_invocation=True)
    warn_sensitive_export_request(args, output)
    started = epoch_now()
    row_count = 0
    with conn, tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=str(output.parent), delete=False) as handle:
        temp_path = Path(handle.name)
        for table in REQUIRED_TABLES:
            if table.startswith("file_") and table.endswith("_rollups"):
                continue
            for payload in export_table_rows(conn, table, repo_id=repo_id):
                payload = sanitize_git_privacy_payload(table, payload, root=root)
                payload = sanitize_import_identity_payload(table, payload, context)
                payload = redact_payload(payload, args)
                pk = table_primary_key(conn, table)
                logical = f"{table}:{payload.get(pk) if pk else sha256_text(json_dumps(payload))}"
                payload_hash = sha256_text(json_dumps(payload))
                row = {
                    "schema_version": SCHEMA_VERSION,
                    "row_type": table,
                    "row_version": SCHEMA_ROW_VERSION,
                    "logical_key": logical,
                    "source_identity": {
                        "db_path_hash": sha256_text(str(db_path)),
                    },
                    "repo_identity": {
                        "repo_id": repo_id,
                        "root_path": (
                            REDACTED_PATH_PREFIX + sha256_text(str(root))
                            if args.redact_paths
                            else protected_repo_path(context, str(root))
                        ),
                    },
                    "payload": payload,
                    "payload_sha256": payload_hash,
                    "exported_epoch": started,
                }
                handle.write(json_dumps(row) + "\n")
                row_count += 1
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp_path, output)
    chmod_private(output)
    digest = sha256_bytes(output.read_bytes())
    finished = epoch_now()
    with conn:
        conn.execute(
            "insert into lattice_exports(repo_id, export_kind, output_path, started_epoch, finished_epoch, row_count, sha256) values (?, 'jsonl', ?, ?, ?, ?, ?)",
            (repo_id, str(output), started, finished, row_count, digest),
        )
        source_id = ensure_source_record(
            conn,
            root,
            repo_id,
            "lattice_export",
            source_path=str(output),
            raw_ref=digest,
            parsed={"row_count": row_count},
            raw_storage_mode=raw_storage_mode,
        )
        record_file_event(conn, repo_id, "export_written", source_id=source_id, path=str(output), details={"row_count": row_count, "sha256": digest})
    print_json({"status": "ok", "output_path": str(output), "row_count": row_count, "sha256": digest})
    return EXIT_SUCCESS


def command_import_jsonl(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    input_path = Path(args.path)
    if not input_path.exists():
        print_json({"status": "unavailable", "reason": "missing_input", "path": str(input_path)})
        return EXIT_USAGE
    if not input_path.is_file():
        print_json({"status": "unavailable", "reason": "input_unreadable", "path": str(input_path)})
        return EXIT_USAGE
    conn = connect_checked(root, normalize_db_path(args.db, root), args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    rows_seen = rows_written = conflicts = duplicates = 0
    refresh_pass_rollup_file_ids: set[int] = set()
    imported_import_max = 0
    try:
        input_lines = input_path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        print_json({"status": "unavailable", "reason": "input_unreadable", "path": str(input_path)})
        return EXIT_USAGE
    for raw in input_lines:
        if not raw:
            continue
        try:
            row = load_strict_json(raw)
        except (TypeError, ValueError, json.JSONDecodeError):
            continue
        if not isinstance(row, dict):
            continue
        if row.get("row_type") != "lattice_imports":
            continue
        payload = row.get("payload")
        if not isinstance(payload, dict):
            continue
        try:
            imported_import_max = max(imported_import_max, int(payload.get("import_id") or 0))
        except (TypeError, ValueError):
            continue
    with conn:
        repo_id = ensure_repository(conn, root)
        context = repo_identity_context(root)
        conn.execute("PRAGMA defer_foreign_keys=ON")
        existing_import_max = int(conn.execute("select coalesce(max(import_id), 0) from lattice_imports").fetchone()[0] or 0)
        import_id = start_import(
            conn,
            repo_id,
            "lattice_import",
            {"path": str(input_path)},
            forced_id=max(existing_import_max, imported_import_max) + 1,
        )
        for line_number, raw in enumerate(input_lines, start=1):
            if not raw:
                continue
            rows_seen += 1
            try:
                row = load_strict_json(raw)
            except (TypeError, ValueError, json.JSONDecodeError):
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, "jsonl", f"line:{rows_seen}", "", "", "malformed_json")
                continue
            if not isinstance(row, dict):
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, "jsonl", f"line:{rows_seen}", "", "", "unsupported_row")
                continue
            table = row.get("row_type")
            payload = row.get("payload")
            logical_key = str(row.get("logical_key", ""))
            declared_payload_hash = str(row.get("payload_sha256", ""))
            schema_version = row.get("schema_version")
            row_version = row.get("row_version")
            try:
                if require_jsonl_int(schema_version, "schema_version") != SCHEMA_VERSION:
                    raise ValueError
            except (TypeError, ValueError):
                conflicts += 1
                record_import_conflict(
                    conn,
                    import_id,
                    repo_id,
                    str(table),
                    logical_key,
                    "",
                    declared_payload_hash,
                    "schema_mismatch",
                    details={"expected": SCHEMA_VERSION, "received": schema_version},
                )
                continue
            try:
                if require_jsonl_int(row_version, "row_version") != SCHEMA_ROW_VERSION:
                    raise ValueError
            except (TypeError, ValueError):
                conflicts += 1
                record_import_conflict(
                    conn,
                    import_id,
                    repo_id,
                    str(table),
                    logical_key,
                    "",
                    declared_payload_hash,
                    "row_version_mismatch",
                    details={"expected": SCHEMA_ROW_VERSION, "received": row_version},
                )
                continue
            if not isinstance(payload, dict):
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, str(table), logical_key, "", declared_payload_hash, "unsupported_row")
                continue
            if has_redacted_path_token(payload):
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, str(table), logical_key, "", declared_payload_hash, "redacted_path_payload")
                continue
            incoming_raw_hash = sha256_text(json_dumps(payload))
            if declared_payload_hash != incoming_raw_hash:
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, str(table), logical_key, "", incoming_raw_hash, "payload_hash_mismatch")
                continue
            payload = sanitize_import_identity_payload(str(table), payload, context)
            if table == "lattice_unavailable" and isinstance(payload, dict):
                # Recovery spool rows can contain DB paths and prior failure text;
                # default imports keep only a hashed summary unless raw retention
                # is explicitly requested and raw storage mode allows it.
                ensure_source_record(
                    conn,
                    root,
                    repo_id,
                    "recovery",
                    source_path=str(input_path),
                    raw_ref=logical_key,
                    raw_text=raw if not getattr(args, "redact_raw", False) else None,
                    parsed=summarize_lattice_unavailable_payload(payload, raw),
                    parse_status="spooled_lattice_unavailable",
                    fact_confidence="observed",
                    source_line=line_number,
                    raw_sha256=sha256_text(raw),
                    raw_storage_mode=raw_storage_mode,
                )
                rows_written += 1
                continue
            if table not in REQUIRED_TABLES:
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, str(table), logical_key, "", incoming_raw_hash, "unsupported_row")
                continue
            columns = table_columns(conn, table)
            pk = table_primary_key(conn, table)
            filtered = {k: v for k, v in payload.items() if k in columns}
            if table == "source_records":
                filtered = sanitize_imported_source_record_row(
                    filtered,
                    root=root,
                    redact_raw=bool(getattr(args, "redact_raw", False)),
                    raw_storage_mode=raw_storage_mode,
                )
            try:
                filtered = normalize_imported_stored_rel_path_payload(str(table), filtered)
            except ValueError as exc:
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, str(table), logical_key, "", incoming_raw_hash, str(exc))
                continue
            if not filtered:
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, table, logical_key, "", incoming_raw_hash, "empty_filtered_payload")
                continue
            incoming_semantic_hash = sha256_text(json_dumps(semantic_import_payload(table, filtered)))
            existing = None
            if pk and filtered.get(pk) is not None:
                existing = conn.execute(f"select * from {table} where {pk}=?", (filtered[pk],)).fetchone()
            if existing:
                existing_payload = semantic_import_payload(table, {key: existing[key] for key in columns})
                existing_hash = sha256_text(json_dumps(existing_payload))
                incoming_compare_payload = align_redacted_import_compare_payload(
                    semantic_import_payload(table, filtered),
                    existing_payload,
                )
                incoming_compare_hash = sha256_text(json_dumps(incoming_compare_payload))
                if existing_hash == incoming_compare_hash:
                    duplicates += 1
                    continue
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, table, logical_key, existing_hash, incoming_compare_hash, "kept_existing")
                continue
            colnames = list(filtered.keys())
            placeholders = ",".join("?" for _ in colnames)
            try:
                conn.execute(
                    f"insert into {table}({', '.join(colnames)}) values ({placeholders})",
                    [filtered[key] for key in colnames],
                )
                rows_written += 1
                if table == "file_pass_runs":
                    try:
                        pass_file_id = int(filtered.get("file_id", 0))
                    except (TypeError, ValueError):
                        pass_file_id = 0
                    if pass_file_id > 0:
                        refresh_pass_rollup_file_ids.add(pass_file_id)
            except sqlite3.IntegrityError as exc:
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, table, logical_key, "", incoming_semantic_hash, f"integrity_error:{exc}")
        finish_import(
            conn,
            import_id,
            "conflicts" if conflicts else "ok",
            rows_seen,
            rows_written,
            conflicts,
            {"duplicates": duplicates},
        )
        if refresh_pass_rollup_file_ids:
            refresh_rollups(conn, repo_id, file_ids=refresh_pass_rollup_file_ids)
        record_file_event(conn, repo_id, "import_reconciled", details={"path": str(input_path), "conflicts": conflicts})
    status = "conflicts" if conflicts else "ok"
    print_json({"status": status, "rows_seen": rows_seen, "rows_written": rows_written, "duplicates": duplicates, "conflicts": conflicts})
    if conflicts > args.max_conflicts:
        return EXIT_IMPORT_CONFLICT
    return EXIT_SUCCESS


def record_import_conflict(
    conn: sqlite3.Connection,
    import_id: int,
    repo_id: int,
    row_type: str,
    logical_key: str,
    existing_hash: str,
    incoming_hash: str,
    resolution: str,
    *,
    details: dict[str, Any] | None = None,
) -> None:
    details_payload = {"resolution": resolution}
    if details:
        details_payload.update(details)
    conn.execute(
        """
        insert into lattice_import_conflicts(import_id, repo_id, row_type, logical_key, existing_hash, incoming_hash, resolution, details_json)
        values (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            import_id,
            repo_id,
            row_type,
            logical_key,
            existing_hash or None,
            incoming_hash or None,
            resolution,
            json_dumps(details_payload),
        ),
    )


def create_backup(
    conn: sqlite3.Connection,
    root: Path,
    db_path: Path,
    output: str | None = None,
    *,
    allow_overwrite: bool = False,
) -> Path:
    if output:
        backup_path = validate_lattice_output_path(
            root,
            output,
            allow_existing=allow_overwrite,
            journal_mode=conn.execute("PRAGMA journal_mode").fetchone()[0].strip().lower(),
            db_path=db_path,
            allow_outside_runtime=True,
        )
    else:
        backup_dir = db_path.parent / "backups"
        if not backup_dir.exists():
            backup_dir.mkdir(parents=True, exist_ok=True)
            chmod_private(backup_dir, is_dir=True, created_by_invocation=True)
        backup_path = backup_dir / f"lattice-backup-{epoch_now()}.sqlite3"
    if not backup_path.parent.exists():
        backup_path.parent.mkdir(parents=True, exist_ok=True)
        chmod_private(backup_path.parent, is_dir=True, created_by_invocation=True)
    if backup_path.exists() or backup_path.is_symlink():
        try:
            existing = backup_path.lstat()
        except OSError as exc:
            fail(f"backup path not stat-able: {backup_path} ({exc})", EXIT_DB_UNAVAILABLE)
        if stat.S_ISLNK(existing.st_mode):
            fail(f"backup path is a symlink: {backup_path}", EXIT_USAGE)
        if not stat.S_ISREG(existing.st_mode):
            fail(f"backup path is not regular: {backup_path}", EXIT_USAGE)
    if conn.in_transaction:
        conn.commit()
    backup_conn = sqlite3.connect(str(backup_path))
    try:
        backup_conn.execute("PRAGMA busy_timeout=5000")
        if backup_conn.in_transaction:
            backup_conn.commit()
        conn.backup(backup_conn, pages=128, sleep=0.01)
        backup_conn.commit()
    finally:
        backup_conn.close()
    chmod_private(backup_path)
    return backup_path


def command_backup(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    db_path = normalize_db_path(args.db, root)
    conn = connect_checked(root, db_path, args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    backup_path = create_backup(
        conn,
        root,
        db_path,
        output=args.output,
        allow_overwrite=args.overwrite,
    )
    conn.close()
    print_json({"status": "ok", "backup_path": str(backup_path)})
    return EXIT_SUCCESS


def record_recovery_artifact_tree(
    conn: sqlite3.Connection,
    root: Path,
    repo_id: int,
    source_id: int,
    artifact_kind: str,
    root_path: Path,
    *,
    limit: int = 500,
) -> int:
    if not root_path.exists():
        return 0
    try:
        root_entry = root_path.lstat()
    except OSError:
        return 0
    if root_entry and stat.S_ISLNK(root_entry.st_mode):
        return 0
    if root_path.is_file():
        files = [root_path]
    else:
        files = []
        for dirpath, dirnames, filenames in os.walk(root_path, followlinks=False):
            dirnames[:] = [name for name in dirnames if not os.path.islink(os.path.join(dirpath, name))]
            for name in filenames:
                path = Path(dirpath) / name
                try:
                    entry = path.lstat()
                except OSError:
                    continue
                if stat.S_ISREG(entry.st_mode) and not os.path.islink(path):
                    files.append(path)
        files.sort()
    count = 0
    for path in files[:limit]:
        create_artifact_ref(
            conn,
            root,
            repo_id,
            cycle_pk=None,
            source_id=source_id,
            artifact_kind=artifact_kind,
            path=str(path),
            dedupe_identity=True,
            details={"recovery_scan_scope": "runtime_tree"},
        )
        count += 1
    return count


def safe_recovery_root(root: Path, raw: Path) -> Path | None:
    runtime_root = (root / "runtime").resolve()
    try:
        normalized = raw.resolve()
    except OSError:
        return None
    if not path_under(normalized, runtime_root):
        return None
    try:
        entry = normalized.lstat()
    except OSError:
        return None
    if not stat.S_ISDIR(entry.st_mode):
        return None
    return normalized


def recover_artifact_refs(
    root: Path,
    db_path: Path,
    journal_mode: str,
    *,
    allow_unsafe_db: bool,
    raw_storage_mode: str | None = None,
) -> list[str]:
    conn = connect_checked(root, db_path, journal_mode, allow_unsafe_db=allow_unsafe_db)
    ensure_schema(conn)
    recorded: list[str] = []
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(
            conn,
            root,
            repo_id,
            "recovery",
            raw_ref="recover_artifacts",
            raw_storage_mode=raw_storage_mode,
        )
        artifact_roots = [
            ("startup_anomaly_state", root / "runtime/startup-anomaly-gates"),
            ("transcript", root / "runtime/upkeeper-transcripts"),
            ("postmortem_report", root / "runtime/journals/upkeeper-postmortems"),
        ]
        for env_name in ("CODEX_WRAPPER_HEALTH_STATE_DIR", "CODEX_WRAPPER_HEALTH_ARCHIVE_DIR"):
            configured = os.environ.get(env_name)
            if configured:
                candidate = safe_recovery_root(root, Path(configured))
                if candidate:
                    artifact_roots.append(("wrapper_health_state", candidate))
        for artifact_kind, artifact_root in artifact_roots:
            count = record_recovery_artifact_tree(conn, root, repo_id, source_id, artifact_kind, artifact_root)
            if count:
                recorded.append(f"{artifact_kind}:{artifact_retention_class(artifact_kind)}:{count}")
        for log_artifact in sorted(root.glob("Upkeeper.log.*")):
            count = record_recovery_artifact_tree(conn, root, repo_id, source_id, "upkeeper_log", log_artifact, limit=1)
            if count:
                recorded.append(f"upkeeper_log:{artifact_retention_class('upkeeper_log')}:{count}")
        quota_root = root / "runtime/journals/upkeeper-postmortems"
        if quota_root.exists():
            for marker in sorted(quota_root.rglob("primary-quota-blocked-until.txt")):
                count = record_recovery_artifact_tree(conn, root, repo_id, source_id, "quota_block_marker", marker, limit=1)
                if count:
                    recorded.append(f"quota_block_marker:{artifact_retention_class('quota_block_marker')}:{count}")
    conn.close()
    return recorded


def command_recover(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    db_path = normalize_db_path(args.db, root)
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    preexisting_db = db_path.exists()
    conn = connect_checked(
        root,
        db_path,
        args.journal_mode,
        allow_unsafe_db=args.allow_unsafe_db,
        create_parent=True,
        create_if_missing=True,
    )
    init_schema(conn, root, raw_storage_mode=raw_storage_mode)
    sources = []
    backup_path = None
    if args.backup_first and preexisting_db:
        backup_path = db_path.parent / "backups" / f"lattice-backup-{epoch_now()}.sqlite3"
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(
            conn,
            root,
            repo_id,
            "recovery",
            raw_ref="recover",
            parsed={"root_hmac": artifact_path_hmac(root, str(root)), "mode": "counts_and_classes"},
            raw_storage_mode=raw_storage_mode,
        )
    if args.backup_first and preexisting_db:
        backup_path = create_backup(
            conn,
            root,
            db_path,
            output=str(backup_path),
            allow_overwrite=False,
        )
        backup_conn = sqlite3.connect(str(backup_path))
        try:
            backup_conn.row_factory = sqlite3.Row
            backup_conn.execute("PRAGMA busy_timeout=5000")
            backup_conn.execute("PRAGMA foreign_keys=ON")
            create_artifact_ref(
                backup_conn,
                root,
                repo_id,
                cycle_pk=None,
                source_id=source_id,
                artifact_kind="backup",
                path=str(backup_path),
                details={"backup_event": "pre_recovery", "recorded_in": "backup"},
            )
            backup_conn.commit()
        finally:
            backup_conn.close()
        sources.append("backup:1")
    conn.close()
    status = "ok"
    if inside_git_repo(root):
        args.raw_storage_mode = raw_storage_mode
        rc = command_import_git(args)
        sources.append(f"git:{rc}")
    log_path = root / "Upkeeper.log"
    if log_path.exists():
        log_args = argparse.Namespace(**vars(args))
        log_args.path = str(log_path)
        log_args.raw = False
        log_args.raw_storage_mode = raw_storage_mode
        command_import_upkeeper_log(log_args)
        sources.append("upkeeper_log_import:1")
    change_notes = sorted(root.glob("change_notes_*.md"))
    if change_notes:
        notes_args = argparse.Namespace(**vars(args))
        notes_args.paths = [str(p) for p in change_notes]
        notes_args.raw = False
        notes_args.raw_storage_mode = raw_storage_mode
        command_import_change_notes(notes_args)
        sources.append(f"change_notes_import:{len(change_notes)}")
    exports = sorted((db_path.parent / "exports").glob("*.jsonl"))
    for export in exports:
        import_args = argparse.Namespace(**vars(args))
        import_args.path = str(export)
        import_args.max_conflicts = args.max_conflicts
        import_args.raw_storage_mode = raw_storage_mode
        command_import_jsonl(import_args)
    if exports:
        sources.append(f"export_import:{len(exports)}")
    recovery_jsonls = sorted((db_path.parent / "recovery").glob("*.jsonl"))
    for recovery_jsonl in recovery_jsonls:
        import_args = argparse.Namespace(**vars(args))
        import_args.path = str(recovery_jsonl)
        import_args.max_conflicts = args.max_conflicts
        import_args.raw_storage_mode = raw_storage_mode
        command_import_jsonl(import_args)
    if recovery_jsonls:
        sources.append(f"recovery_import:{len(recovery_jsonls)}")
    for marker_root in [root / "runtime/unaddressed-tool-failures/open", root / "runtime/unaddressed-tool-failures/resolved"]:
        if marker_root.exists():
            import_failure_markers(
                root,
                db_path,
                args.journal_mode,
                marker_root,
                allow_unsafe_db=args.allow_unsafe_db,
                raw_storage_mode=raw_storage_mode,
            )
            sources.append("tool_failure_marker_import:1")
    sources.extend(
        recover_artifact_refs(
            root,
            db_path,
            args.journal_mode,
            allow_unsafe_db=args.allow_unsafe_db,
            raw_storage_mode=raw_storage_mode,
        )
    )
    if not sources:
        status = "incomplete"
    recovery_dir = db_path.parent / "recovery"
    if not recovery_dir.exists():
        recovery_dir.mkdir(parents=True, exist_ok=True)
        chmod_private(recovery_dir, is_dir=True, created_by_invocation=True)
    report_path = recovery_dir / f"recovery-{epoch_now()}.json"
    report = {"status": status, "sources": sources}
    report_path.write_text(json_dumps(report) + "\n", encoding="utf-8")
    chmod_private(report_path)
    print_json({"status": status, "sources": sources, "recovery_report": str(report_path)})
    return EXIT_SUCCESS if status == "ok" else EXIT_RECOVERY_INCOMPLETE


def import_failure_markers(
    root: Path,
    db_path: Path,
    journal_mode: str,
    marker_root: Path,
    *,
    allow_unsafe_db: bool,
    raw_storage_mode: str | None = None,
) -> None:
    conn = connect_checked(root, db_path, journal_mode, allow_unsafe_db=allow_unsafe_db)
    ensure_schema(conn)
    with conn:
        repo_id = ensure_repository(conn, root)
        for path in marker_root.glob("*.json"):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            target, marker_id, raw_marker_id = tool_failure_marker_identity(root, path, data)
            if not target or not marker_id:
                continue
            file_id = ensure_file(conn, repo_id, target)
            source_id = ensure_source_record(
                conn,
                root,
                repo_id,
                "tool_failure_marker",
                source_path=str(path),
                raw_ref=raw_marker_id,
                parsed=data,
                raw_storage_mode=raw_storage_mode,
            )
            conn.execute(
                """
                insert into tool_failures(
                  repo_id, file_id, marker_id, status, first_seen_epoch, last_seen_epoch, resolved_epoch,
                  first_failure_kind, last_failure_kind, failure_count, source_id, raw_json
                ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    repo_id,
                    file_id,
                    marker_id,
                    str(data.get("status", "open")),
                    int(data.get("first_seen_epoch") or 0) or None,
                    int(data.get("last_seen_epoch") or 0) or None,
                    int(data.get("resolved_epoch") or 0) or None,
                    data.get("first_failure_kind"),
                    data.get("last_failure_kind"),
                    int(data.get("failure_count") or 0) or None,
                    source_id,
                    json_dumps(data),
                ),
            )
            record_file_event(conn, repo_id, "tool_failure_resolved" if data.get("status") == "resolved" else "tool_failure_opened", file_id=file_id, source_id=source_id, path=target, details=data)


def pass_counts_for_path(conn: sqlite3.Connection, repo_id: int, path: str, pass_code: str | None = None) -> list[dict[str, Any]]:
    file_id = file_id_for_path(conn, repo_id, path)
    if not file_id:
        return []
    params: list[Any] = [repo_id, file_id]
    where = "where repo_id=? and file_id=?"
    if pass_code:
        where += " and pass_code=?"
        params.append(normalize_pass_code(pass_code))
    rows = conn.execute(
        f"""
        select pass_code,
          sum(case when planned=1 then 1 else 0 end) as planned_count,
          sum(case when applicable=1 then 1 else 0 end) as applicable_count,
          sum(case when attempted=1 then 1 else 0 end) as attempted_count,
          sum(case when outcome in ('clean','fixed','regression_found') then 1 else 0 end) as completed_count,
          sum(case when outcome='blocked' then 1 else 0 end) as blocked_count,
          sum(case when changed=1 then 1 else 0 end) as changed_count,
          sum(case when outcome='clean' then 1 else 0 end) as clean_count,
          sum(case when outcome='not_applicable' then 1 else 0 end) as not_applicable_count,
          sum(case when outcome='unknown' then 1 else 0 end) as unknown_count,
          sum(case when regression=1 or outcome='regression_found' then 1 else 0 end) as regression_count
        from file_pass_runs
        {where}
        group by pass_code
        order by pass_code
        """,
        params,
    )
    return [dict(row) | {"path": path} for row in rows]


def query_never_pass(conn: sqlite3.Connection, root: Path, repo_id: int, args: argparse.Namespace) -> list[dict[str, Any]]:
    pass_code = normalize_pass_code(args.pass_code)
    paths = current_scope_paths(conn, root, repo_id, args.scope)
    rows = []
    for path in paths:
        file_id = file_id_for_path(conn, repo_id, path)
        completed = 0
        if file_id:
            completed = int(
                conn.execute(
                    """
                    select count(*) from file_pass_runs
                    where repo_id=? and file_id=? and pass_code=? and outcome in ('clean','fixed','regression_found')
                    """,
                    (repo_id, file_id, pass_code),
                ).fetchone()[0]
            )
        if completed == 0:
            rows.append({"path": path, "pass_code": pass_code, "completed_count": 0, "scope": args.scope})
    return rows


def query_pass_counts(conn: sqlite3.Connection, root: Path, repo_id: int, args: argparse.Namespace) -> list[dict[str, Any]]:
    return pass_counts_for_path(conn, repo_id, external_rel_path(args.path), args.pass_code)


def query_file_history(conn: sqlite3.Connection, root: Path, repo_id: int, args: argparse.Namespace) -> list[dict[str, Any]]:
    path = external_rel_path(args.path)
    file_id = file_id_for_path(conn, repo_id, path)
    if not file_id:
        return []
    rows: list[dict[str, Any]] = []
    for row in conn.execute(
        """
        select event_epoch as epoch, event_kind as kind, path, confidence, details_json
        from file_events where repo_id=? and file_id=?
        order by event_epoch, event_id
        """,
        (repo_id, file_id),
    ):
        rows.append(dict(row))
    git_commit_columns = set(table_columns(conn, "git_commits"))
    subject_hash_expr = "c.subject_hash as subject_hash" if "subject_hash" in git_commit_columns else "null as subject_hash"
    subject_length_expr = "c.subject_length as subject_length" if "subject_length" in git_commit_columns else "null as subject_length"
    subject_included_expr = "c.subject_included as subject_included" if "subject_included" in git_commit_columns else "0 as subject_included"
    for row in conn.execute(
        f"""
        select g.change_epoch as epoch, 'git_change' as kind, g.path, g.status, c.sha, c.subject,
               {subject_hash_expr}, {subject_length_expr}, {subject_included_expr}
        from git_file_changes g join git_commits c on c.commit_id=g.commit_id
        where g.repo_id=? and g.file_id=?
        order by g.change_epoch, g.git_file_change_id
        """,
        (repo_id, file_id),
    ):
        payload = dict(row)
        payload.update(
            commit_subject_summary(
                payload.get("subject") if isinstance(payload.get("subject"), str) else None,
                payload.get("subject_hash"),
                payload.get("subject_length"),
                payload.get("subject_included"),
            )
        )
        rows.append(payload)
    return sorted(rows, key=lambda item: (item.get("epoch") or 0, str(item.get("kind"))))


def query_regressions(conn: sqlite3.Connection, root: Path, repo_id: int, args: argparse.Namespace) -> list[dict[str, Any]]:
    params: list[Any] = [repo_id]
    where = "where r.repo_id=?"
    if args.path:
        file_id = file_id_for_path(conn, repo_id, args.path)
        if not file_id:
            return []
        where += " and r.file_id=?"
        params.append(file_id)
    return [
        dict(row)
        for row in conn.execute(
            f"""
            select f.current_path as path, r.marked_epoch, r.confidence, r.detector, r.reason, r.status,
                   c.cycle_id
            from regression_events r
            left join files f on f.file_id=r.file_id
            left join cycles c on c.cycle_pk=r.cycle_pk
            {where}
            order by r.marked_epoch desc
            """,
            params,
        )
    ]


def query_least_reviewed(conn: sqlite3.Connection, root: Path, repo_id: int, args: argparse.Namespace) -> list[dict[str, Any]]:
    paths = current_scope_paths(conn, root, repo_id, args.scope)
    rows = []
    for path in paths:
        file_id = file_id_for_path(conn, repo_id, path)
        completed_pass_count = completed_cycle_count = 0
        last_epoch = None
        if file_id:
            completed_pass_count = int(
                conn.execute(
                    "select count(*) from file_pass_runs where repo_id=? and file_id=? and outcome in ('clean','fixed','regression_found')",
                    (repo_id, file_id),
                ).fetchone()[0]
            )
            cycle_rows = conn.execute(
                """
                select distinct c.cycle_pk, coalesce(c.end_epoch, c.start_epoch) as epoch
                from file_pass_runs p join cycles c on c.cycle_pk=p.cycle_pk
                where p.repo_id=? and p.file_id=? and p.outcome in ('clean','fixed','regression_found')
                """,
                (repo_id, file_id),
            ).fetchall()
            completed_cycle_count = len(cycle_rows)
            epochs = [row["epoch"] for row in cycle_rows if row["epoch"] is not None]
            last_epoch = max(epochs) if epochs else None
        mtime = live_file_metadata(root, path).get("mtime_epoch")
        rows.append(
            {
                "path": path,
                "completed_pass_count": completed_pass_count,
                "completed_cycle_count": completed_cycle_count,
                "last_completed_cycle_epoch": last_epoch,
                "mtime_epoch": mtime,
                "scope": args.scope,
            }
        )
    return sorted(
        rows,
        key=lambda r: (
            r["completed_pass_count"],
            r["completed_cycle_count"],
            r["last_completed_cycle_epoch"] is not None,
            r["last_completed_cycle_epoch"] or 0,
            r["mtime_epoch"] or 0,
            r["path"],
        ),
    )


def query_most_fragile(conn: sqlite3.Connection, root: Path, repo_id: int, args: argparse.Namespace) -> list[dict[str, Any]]:
    paths = current_scope_paths(conn, root, repo_id, args.scope)
    rows = []
    for path in paths:
        file_id = file_id_for_path(conn, repo_id, path)
        if not file_id:
            continue
        active_asserted = scalar_count(conn, "regression_events", "repo_id=? and file_id=? and status='active' and confidence='asserted'", (repo_id, file_id))
        active_inferred = scalar_count(conn, "regression_events", "repo_id=? and file_id=? and status='active' and confidence='inferred'", (repo_id, file_id))
        active_suspected = scalar_count(conn, "regression_events", "repo_id=? and file_id=? and status='active' and confidence='suspected'", (repo_id, file_id))
        open_failures = scalar_count(conn, "tool_failures", "repo_id=? and file_id=? and status='open'", (repo_id, file_id))
        blocked = scalar_count(conn, "file_pass_runs", "repo_id=? and file_id=? and outcome='blocked'", (repo_id, file_id))
        clean_touches = scalar_count(conn, "file_events", "repo_id=? and file_id=? and event_kind='touched_clean'", (repo_id, file_id))
        last_completed = conn.execute(
            "select max(created_epoch) from file_pass_runs where repo_id=? and file_id=? and outcome in ('clean','fixed','regression_found')",
            (repo_id, file_id),
        ).fetchone()[0]
        if last_completed:
            churn = scalar_count(conn, "git_file_changes", "repo_id=? and file_id=? and change_epoch>?", (repo_id, file_id, last_completed))
        else:
            churn = scalar_count(conn, "git_file_changes", "repo_id=? and file_id=?", (repo_id, file_id))
        score = 10 * active_asserted + 6 * active_inferred + 3 * active_suspected + 4 * open_failures + 2 * blocked + clean_touches + min(10, churn)
        rows.append(
            {
                "path": path,
                "score_version": 1,
                "score": score,
                "active_asserted_regressions": active_asserted,
                "active_inferred_regressions": active_inferred,
                "active_suspected_regressions": active_suspected,
                "open_tool_failures": open_failures,
                "blocked_passes": blocked,
                "repeated_clean_touches_after_failures": clean_touches,
                "git_churn_count_since_last_completed_pass": churn,
            }
        )
    return sorted(rows, key=lambda r: (-r["score"], r["path"]))


def scalar_count(conn: sqlite3.Connection, table: str, where: str, params: tuple[Any, ...]) -> int:
    return int(conn.execute(f"select count(*) from {table} where {where}", params).fetchone()[0])


def query_changed_since_last_pass(conn: sqlite3.Connection, root: Path, repo_id: int, args: argparse.Namespace) -> list[dict[str, Any]]:
    pass_code = normalize_pass_code(args.pass_code)
    paths = current_scope_paths(conn, root, repo_id, args.scope)
    rows = []
    for path in paths:
        file_id = file_id_for_path(conn, repo_id, path)
        latest_pass = None
        latest_git = None
        changed = True
        reason = "no_completed_pass"
        if file_id:
            latest_pass = conn.execute(
                """
                select max(created_epoch) from file_pass_runs
                where repo_id=? and file_id=? and pass_code=? and outcome in ('clean','fixed','regression_found')
                """,
                (repo_id, file_id, pass_code),
            ).fetchone()[0]
            latest_git = conn.execute(
                "select max(change_epoch) from git_file_changes where repo_id=? and file_id=?",
                (repo_id, file_id),
            ).fetchone()[0]
            if latest_pass and latest_git and latest_git > latest_pass:
                changed = True
                reason = "git_change_newer_than_pass"
            elif latest_pass:
                snap = conn.execute(
                    """
                    select worktree_hash from file_snapshots
                    where repo_id=? and file_id=? and observed_epoch<=?
                    order by observed_epoch desc limit 1
                    """,
                    (repo_id, file_id, latest_pass),
                ).fetchone()
                current_hash = live_file_metadata(root, path).get("worktree_hash")
                if snap and snap["worktree_hash"] and current_hash and snap["worktree_hash"] != current_hash:
                    changed = True
                    reason = "worktree_hash_changed"
                else:
                    changed = False
                    reason = "unchanged_since_completed_pass"
        if changed:
            rows.append({"path": path, "pass_code": pass_code, "reason": reason, "latest_completed_pass_epoch": latest_pass, "latest_git_change_epoch": latest_git})
    return rows


def pass_coverage_counts_for_file(conn: sqlite3.Connection, repo_id: int, file_id: int | None) -> dict[str, int]:
    counts = {item["pass_code"]: 0 for item in PASS_REGISTRY if item.get("active", True)}
    if not file_id:
        return counts
    for row in conn.execute(
        """
        select pass_code,
          sum(
            case
              when outcome in ('clean','fixed','regression_found','not_applicable','blocked') then 1
              when attempted=1 then 1
              else 0
            end
          ) as covered_count
        from file_pass_runs
        where repo_id=? and file_id=?
        group by pass_code
        """,
        (repo_id, file_id),
    ):
        pass_code = normalize_pass_code(str(row["pass_code"]))
        if pass_code in counts:
            counts[pass_code] = int(row["covered_count"] or 0)
    return counts


def annotate_max_cover_scores(conn: sqlite3.Connection, repo_id: int, rows: list[dict[str, Any]]) -> None:
    for row in rows:
        if row["candidate_state"] != "eligible":
            continue
        file_id = file_id_for_path(conn, repo_id, row["path"])
        counts = pass_coverage_counts_for_file(conn, repo_id, file_id)
        unrun = sorted(pass_code for pass_code, count in counts.items() if count == 0)
        min_count = min(counts.values()) if counts else 0
        row["score_json"] = json_dumps(
            {
                "coverage_mode": "max-cover",
                "pass_count": len(counts),
                "unrun_pass_count": len(unrun),
                "oldest_unrun_pass": unrun[0] if unrun else "",
                "least_covered_count": min_count,
            }
        )


def query_selection_candidates(conn: sqlite3.Connection, root: Path, repo_id: int, args: argparse.Namespace) -> list[dict[str, Any]]:
    mode = args.mode
    candidate_scope = "current-tracked" if mode == "max-cover" else "eligible"
    rows = live_candidate_paths(root, candidate_scope=candidate_scope, upkeeper_ignore_file=getattr(args, "upkeeper_ignore_file", None))
    eligible = [row for row in rows if row["candidate_state"] == "eligible"]
    excluded = [row for row in rows if row["candidate_state"] != "eligible"]
    if mode == "max-cover":
        annotate_max_cover_scores(conn, repo_id, eligible)
        eligible.sort(
            key=lambda r: (
                0 if json.loads(r.get("score_json") or "{}").get("unrun_pass_count", 0) else 1,
                json.loads(r.get("score_json") or "{}").get("least_covered_count", 0),
                r.get("mtime_epoch") or 0,
                r["path"],
            )
        )
    elif mode.startswith("never-pass:"):
        pass_code = normalize_pass_code(mode.split(":", 1)[1])
        for row in eligible:
            counts = pass_counts_for_path(conn, repo_id, row["path"], pass_code)
            completed = sum(int(c.get("completed_count") or 0) for c in counts)
            row["score_json"] = json_dumps({"pass_code": pass_code, "completed_count": completed})
        eligible.sort(key=lambda r: (json.loads(r["score_json"])["completed_count"], r.get("mtime_epoch") or 0, r["path"]))
    elif mode == "least-reviewed":
        least_args = argparse.Namespace(scope="current-eligible")
        order = {row["path"]: i for i, row in enumerate(query_least_reviewed(conn, root, repo_id, least_args))}
        eligible.sort(key=lambda r: (order.get(r["path"], 999999), r["path"]))
    elif mode == "most-fragile":
        frag_args = argparse.Namespace(scope="current-eligible")
        scores = {row["path"]: row["score"] for row in query_most_fragile(conn, root, repo_id, frag_args)}
        eligible.sort(key=lambda r: (-scores.get(r["path"], 0), r["path"]))
    elif mode.startswith("changed-since-last-pass:"):
        pass_code = normalize_pass_code(mode.split(":", 1)[1])
        changed_args = argparse.Namespace(scope="current-eligible", pass_code=pass_code)
        changed = {row["path"] for row in query_changed_since_last_pass(conn, root, repo_id, changed_args)}
        eligible.sort(key=lambda r: (0 if r["path"] in changed else 1, r.get("mtime_epoch") or 0, r["path"]))
    else:
        eligible.sort(key=lambda r: (r.get("mtime_epoch") or 0, r["path"]))
    for rank, row in enumerate(eligible, start=1):
        row["rank"] = rank
        row["mode"] = mode
    for row in excluded:
        row["rank"] = None
        row["mode"] = mode
    return eligible + sorted(excluded, key=lambda r: (r.get("exclusion_reason") or "", r["path"]))


def query_explain_selection(conn: sqlite3.Connection, root: Path, repo_id: int, args: argparse.Namespace) -> list[dict[str, Any]]:
    params: list[Any] = [repo_id]
    where = "where s.repo_id=?"
    if args.cycle_id:
        where += " and c.cycle_id=?"
        params.append(args.cycle_id)
    if args.path:
        where += " and s.selected_path=?"
        params.append(stored_rel_path(external_rel_path(args.path)))
    rows = []
    for row in conn.execute(
        f"""
        select s.*, c.cycle_id
        from selection_runs s
        left join cycles c on c.cycle_pk=s.cycle_pk
        {where}
        order by s.generated_epoch desc limit 20
        """,
        params,
    ):
        item = dict(row)
        counts = {
            r["candidate_state"]: r["count"]
            for r in conn.execute(
                "select candidate_state, count(*) as count from selection_candidates where selection_run_id=? group by candidate_state",
                (row["selection_run_id"],),
            )
        }
        exclusions = {
            str(r["exclusion_reason"]): r["count"]
            for r in conn.execute(
                """
                select coalesce(exclusion_reason, 'none') as exclusion_reason, count(*) as count
                from selection_candidates
                where selection_run_id=? and candidate_state='excluded'
                group by coalesce(exclusion_reason, 'none')
                """,
                (row["selection_run_id"],),
            )
        }
        better = [
            dict(r)
            for r in conn.execute(
                """
                select path, rank, candidate_state, exclusion_reason, score_json
                from selection_candidates
                where selection_run_id=? and rank is not null and rank < ?
                order by rank
                """,
                (row["selection_run_id"], row["selected_rank"] or 999999),
            )
        ]
        item.update(
            {
                "candidate_counts": counts,
                "exclusion_counts": exclusions,
                "failure_queue_influence": row["priority_gate"] == "failure_queue",
                "startup_anomaly_influence": row["priority_gate"] == "startup_anomaly",
                "stale_self_review_influence": row["priority_gate"] == "stale_self_review",
                "higher_candidates": better,
            }
        )
        rows.append(item)
    return rows


def command_query(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    conn = connect_checked(root, normalize_db_path(args.db, root), args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    conn.execute("PRAGMA query_only = ON")
    with conn:
        repo_id = lookup_repository_id(conn, root)
    if repo_id is None:
        fail(
            "repository metadata is not initialized in this lattice DB for this repository; "
            "run a write command (for example `record-cycle-start` or `import-git`) before querying",
            EXIT_USAGE,
        )
    query_name = args.query_name
    if query_name == "never-pass":
        rows = query_never_pass(conn, root, repo_id, args)
    elif query_name == "pass-counts":
        rows = query_pass_counts(conn, root, repo_id, args)
    elif query_name == "file-history":
        rows = query_file_history(conn, root, repo_id, args)
    elif query_name == "regressions":
        rows = query_regressions(conn, root, repo_id, args)
    elif query_name == "least-reviewed":
        rows = query_least_reviewed(conn, root, repo_id, args)
    elif query_name == "most-fragile":
        rows = query_most_fragile(conn, root, repo_id, args)
    elif query_name == "changed-since-last-pass":
        rows = query_changed_since_last_pass(conn, root, repo_id, args)
    elif query_name == "selection-candidates":
        rows = query_selection_candidates(conn, root, repo_id, args)
    elif query_name == "explain-selection":
        rows = query_explain_selection(conn, root, repo_id, args)
    else:
        fail(f"unknown query: {query_name}", EXIT_USAGE)
    format_rows(rows, args.format)
    return EXIT_NO_MATCH if args.fail_on_no_match and not rows else EXIT_SUCCESS


def command_mark_regression(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    conn = connect_checked(root, normalize_db_path(args.db, root), args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(
            conn,
            root,
            repo_id,
            args.source_kind,
            raw_ref="mark-regression",
            parsed=vars(args),
            raw_storage_mode=raw_storage_mode,
        )
        file_id = ensure_file(conn, repo_id, args.path, source_id=source_id)
        cycle_pk = None
        if args.cycle_id:
            row = conn.execute(
                "select cycle_pk from cycles where repo_id=? and cycle_id=? order by cycle_pk desc limit 1",
                (repo_id, args.cycle_id),
            ).fetchone()
            cycle_pk = int(row["cycle_pk"]) if row else None
        cur = conn.execute(
            """
            insert into regression_events(repo_id, file_id, cycle_pk, marked_epoch, confidence, detector, reason, status, source_id)
            values (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (repo_id, file_id, cycle_pk, epoch_now(), args.confidence, args.detector, args.reason, args.status, source_id),
        )
        regression_id = int(cur.lastrowid)
        if args.cause_commit:
            commit_row = conn.execute(
                "select commit_id from git_commits where repo_id=? and sha=?",
                (repo_id, args.cause_commit),
            ).fetchone()
            conn.execute(
                """
                insert into regression_causes(regression_id, suspected_cause_commit_id, cause_file_id, confidence, reason)
                values (?, ?, ?, ?, ?)
                """,
                (regression_id, int(commit_row["commit_id"]) if commit_row else None, file_id, args.confidence, args.reason),
            )
        record_file_event(conn, repo_id, "regression_marked", file_id=file_id, cycle_pk=cycle_pk, source_id=source_id, path=args.path, confidence=args.confidence)
    print_json({"status": "ok", "regression_id": regression_id})
    return EXIT_SUCCESS


def command_prune(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    raw_storage_mode = getattr(args, "raw_storage_mode", None) or current_lattice_raw_storage()
    conn = connect_checked(root, normalize_db_path(args.db, root), args.journal_mode, allow_unsafe_db=args.allow_unsafe_db)
    ensure_schema(conn)
    if args.dry_run:
        conn.execute("PRAGMA query_only = ON")
    cutoff = epoch_now() - int(args.older_than_days or 0) * 86400 if args.older_than_days else None
    actions: list[dict[str, Any]] = []
    repo_id: int | None = None
    with conn:
        if args.dry_run:
            info = repo_git_info(root)
            repo_key = sha256_text(f"{root}|{info['git_common_dir']}|{info['remote_url']}")
            row = conn.execute("select repo_id from repositories where repo_key=?", (repo_key,)).fetchone()
            repo_id = int(row["repo_id"]) if row else None
        else:
            repo_id = ensure_repository(conn, root)
            source_id = ensure_source_record(
                conn,
                root,
                repo_id,
                "operator",
                raw_ref="prune",
                parsed=vars(args),
                raw_storage_mode=raw_storage_mode,
            )
        if args.raw_only:
            if repo_id is None and args.dry_run:
                actions.append({"action": "raw_text_null", "rows": 0, "skipped": "repo_not_registered"})
            else:
                sql = "update source_records set raw_text=null where repo_id=? and raw_text is not null"
                params: list[Any] = [repo_id]
                if cutoff:
                    sql += " and imported_epoch<?"
                    params.append(cutoff)
                select_sql = "select count(*) from source_records where repo_id=? and raw_text is not null"
                if cutoff:
                    select_sql += " and imported_epoch<?"
                count = conn.execute(select_sql, tuple(params)).fetchone()[0]
                actions.append({"action": "raw_text_null", "rows": count})
                if not args.dry_run:
                    conn.execute(sql, tuple(params))
        if args.candidate_details:
            if repo_id is None and args.dry_run:
                actions.append({"action": "candidate_details_delete", "rows": 0, "skipped": "repo_not_registered"})
            else:
                sql = """
                delete from selection_candidates
                  where candidate_state != 'selected'
                  and selection_run_id in (select selection_run_id from selection_runs where repo_id=? and generated_epoch<?)
                """
                count = 0
                if cutoff:
                    count = conn.execute(
                        """
                        select count(*) from selection_candidates
                        where candidate_state != 'selected'
                          and selection_run_id in (select selection_run_id from selection_runs where repo_id=? and generated_epoch<?)
                        """,
                        (repo_id, cutoff),
                    ).fetchone()[0]
                    actions.append({"action": "candidate_details_delete", "rows": count})
                    if not args.dry_run:
                        conn.execute(sql, (repo_id, cutoff))
        if args.transient_artifacts:
            transient_kinds = tuple(sorted(TRANSIENT_ARTIFACT_KINDS))
            placeholders = ",".join("?" for _ in transient_kinds)
            if repo_id is None and args.dry_run:
                actions.append({"action": "transient_artifacts_unretain", "rows": 0, "skipped": "repo_not_registered"})
            else:
                sql = f"""
                    select count(*) from artifact_refs
                    where repo_id=? and retained=1 and artifact_kind in ({placeholders})
                """
                sql_params: list[Any] = [repo_id, *transient_kinds]
                if cutoff:
                    sql += " and observed_epoch < ?"
                    sql_params.append(cutoff)
                row_count = int(conn.execute(sql, sql_params).fetchone()[0] or 0)
                actions.append({"action": "transient_artifacts_unretain", "rows": row_count})
                if not args.dry_run:
                    update_sql = f"""
                        update artifact_refs
                        set retained=0
                        where repo_id=? and retained=1 and artifact_kind in ({placeholders})
                    """
                    update_params: list[Any] = [repo_id, *transient_kinds]
                    if cutoff:
                        update_sql += " and observed_epoch < ?"
                        update_params.append(cutoff)
                    conn.execute(
                        update_sql,
                        update_params,
                    )
        if args.scrub_transient_metadata:
            transient_kinds = tuple(sorted(TRANSIENT_ARTIFACT_KINDS))
            placeholders = ",".join("?" for _ in transient_kinds)
            if repo_id is None and args.dry_run:
                actions.append({"action": "transient_artifacts_scrub", "rows": 0, "skipped": "repo_not_registered"})
            else:
                sql = f"""
                    select count(*) from artifact_refs
                    where repo_id=?
                      and artifact_kind in ({placeholders})
                      and (
                        retained=1
                        or path is not null
                        or size_bytes is not null
                        or sha256 is not null
                        or details_json is not null
                      )
                """
                sql_params: list[Any] = [repo_id, *transient_kinds]
                if cutoff:
                    sql += " and observed_epoch < ?"
                    sql_params.append(cutoff)
                row_count = int(conn.execute(sql, sql_params).fetchone()[0] or 0)
                actions.append({"action": "transient_artifacts_scrub", "rows": row_count})
                if not args.dry_run:
                    update_sql = f"""
                        update artifact_refs
                        set retained=0, path=null, size_bytes=null, sha256=null, details_json=null
                        where repo_id=?
                          and artifact_kind in ({placeholders})
                          and (
                            retained=1
                            or path is not null
                            or size_bytes is not null
                            or sha256 is not null
                            or details_json is not null
                          )
                    """
                    update_params: list[Any] = [repo_id, *transient_kinds]
                    if cutoff:
                        update_sql += " and observed_epoch < ?"
                        update_params.append(cutoff)
                    conn.execute(
                        update_sql,
                        update_params,
                    )
        if not args.dry_run:
            record_file_event(conn, repo_id, "operator_annotation", source_id=source_id, details={"prune_actions": actions, "dry_run": args.dry_run})
        if args.vacuum and not args.dry_run:
            conn.execute("commit")
            conn.execute("vacuum")
            conn.execute("begin")
    print_json({"status": "ok", "dry_run": args.dry_run, "actions": actions})
    return EXIT_SUCCESS


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Upkeeper Lattice local SQLite ledger")
    parser.add_argument("--root", default=str(default_root()), help="repository root")
    parser.add_argument("--db", default=None, help="SQLite DB path")
    parser.add_argument("--journal-mode", default=os.environ.get("UPKEEPER_LATTICE_SQLITE_JOURNAL_MODE", "delete"), choices=["delete", "wal"])
    parser.add_argument("--allow-unsafe-db", action="store_true", default=os.environ.get("UPKEEPER_LATTICE_ALLOW_UNSAFE_DB") == "1")
    parser.add_argument(
        "--raw-repo-identity",
        action="store_true",
        default=os.environ.get(UPKEEPER_RAW_REPO_IDENTITY_ENV) == "1",
        help="opt in to raw path/branch/HTTPS repo identity storage; SSH and local remotes remain redacted",
    )
    parser.add_argument("--upkeeper-ignore-file", default=os.environ.get("CODEX_UPKEEPER_IGNORE_FILE", os.environ.get("UPKEEPER_IGNORE_FILE", ".upkeeperignore")), help="Upkeeper target-selection ignore file")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("init")
    p.set_defaults(func=command_init)

    p = sub.add_parser("doctor")
    p.add_argument("--backup", action="store_true")
    p.add_argument("--backup-output")
    p.set_defaults(func=command_doctor)

    p = sub.add_parser("record-cycle-start")
    add_cycle_args(p)
    p.add_argument("--execution-origin", default=None)
    p.add_argument("--model", default=None)
    p.add_argument("--effort", default=None)
    p.add_argument("--mode", default=None)
    p.add_argument("--config-file", default=None)
    p.add_argument("--branch-name", default=None)
    p.add_argument("--head-sha", default=None)
    p.add_argument("--head-tree-sha", default=None)
    p.add_argument("--upstream-ref", default=None)
    p.add_argument("--dirty-path-count", default=None)
    p.add_argument("--worktree-untracked-files", choices=WORKTREE_SNAPSHOT_UNTRACKED_MODES, default=None)
    p.add_argument("--dry-run", default=None)
    p.add_argument("--start-epoch", type=int)
    p.add_argument("--parent-cycle-id", default="")
    p.add_argument("--child-cycle-id", default="")
    p.add_argument("--fallback-trigger", default="")
    p.set_defaults(func=command_record_cycle_start)

    p = sub.add_parser("record-preselect")
    add_cycle_args(p)
    p.add_argument("--selection-file")
    p.add_argument("--candidate-file")
    p.add_argument("--selector-version", default="help_selection.bash/v1")
    p.add_argument("--source-safe-boundary-version", default="default-review/v1")
    p.add_argument("--selection-mode", default=os.environ.get("UPKEEPER_LATTICE_SELECTION_MODE", "oldest-mtime"))
    p.set_defaults(func=command_record_preselect)

    p = sub.add_parser("record-cycle-finish")
    add_cycle_args(p)
    p.add_argument("--status-marker", default=None)
    p.add_argument("--review-outcome", default=None)
    p.add_argument("--review-selected-path", default=None)
    p.add_argument("--codex-exit", type=int)
    p.add_argument("--wrapper-exit", type=int)
    p.add_argument("--finish-reason", default=None)
    p.add_argument("--finish-level", default=None)
    p.add_argument("--codex-exec-started", type=int, default=None)
    p.add_argument("--dry-run", default=None)
    p.add_argument("--selected-path", default=None)
    p.add_argument("--last-message-file", default=None)
    p.add_argument("--transcript-path", default=None)
    p.add_argument("--compiled-prompt-path", default=None)
    p.add_argument("--log-path", default=None)
    p.add_argument("--transcript-sha256", default=None)
    p.add_argument("--compiled-prompt-sha256", default=None)
    p.add_argument("--last-message-sha256", default=None)
    p.add_argument("--log-sha256", default=None)
    p.add_argument("--snapshot-kind", default="after_codex")
    p.add_argument("--end-epoch", type=int)
    p.set_defaults(func=command_record_cycle_finish)

    p = sub.add_parser("record-worktree-snapshot")
    add_cycle_args(p, required=False)
    p.add_argument("--snapshot-kind", required=True)
    p.add_argument("--worktree-untracked-files", choices=WORKTREE_SNAPSHOT_UNTRACKED_MODES, default=None)
    p.set_defaults(func=command_record_worktree_snapshot)

    p = sub.add_parser("record-pass-result")
    add_cycle_args(p, required=False)
    p.add_argument("--pass", dest="pass_code")
    p.add_argument("--file", dest="path")
    p.add_argument("--path", dest="path")
    p.add_argument("--applicable", default="")
    p.add_argument("--outcome", default="unknown", choices=sorted(ALLOWED_OUTCOMES))
    p.add_argument("--changed", default="")
    p.add_argument("--regression", default="")
    p.add_argument("--raw-line", default="")
    p.add_argument("--attribute", action="append", default=[])
    p.add_argument("--from-file", default="")
    p.add_argument("--selected-path", default="")
    p.add_argument("--planned-pass", action="append", default=[])
    p.add_argument("--planned-passes", default="")
    p.set_defaults(func=command_record_pass_result)

    p = sub.add_parser("import-git")
    p.add_argument("--limit", type=int)
    p.add_argument("--include-contributor-pii", action="store_true")
    p.add_argument("--include-commit-subjects", action="store_true")
    p.set_defaults(func=command_import_git)

    p = sub.add_parser("import-upkeeper-log")
    p.add_argument("--path", default="")
    p.add_argument("--raw", action="store_true")
    p.set_defaults(func=command_import_upkeeper_log)

    p = sub.add_parser("import-change-notes")
    p.add_argument("paths", nargs="*")
    p.add_argument("--raw", action="store_true")
    p.set_defaults(func=command_import_change_notes)

    p = sub.add_parser("export-jsonl")
    p.add_argument("--output")
    p.add_argument("--overwrite", action="store_true")
    p.add_argument(
        "--include-raw",
        dest="raw_export_policy",
        action="store_const",
        const="include",
        help="include raw_text/details_json/parsed_json fields; warns because exports may contain sensitive local evidence",
    )
    p.add_argument(
        "--include-paths",
        dest="redact_paths",
        action="store_false",
        help="include raw paths, remotes, and repo identity values in exported payloads",
    )
    p.add_argument(
        "--include-contributors",
        dest="redact_contributors",
        action="store_false",
        help="include contributor name/email/login fields when the database already stores them",
    )
    p.add_argument("--redact-raw", dest="raw_export_policy", action="store_const", const="structured_redact", help=argparse.SUPPRESS)
    p.add_argument("--redact-paths", dest="redact_paths", action="store_true", help=argparse.SUPPRESS)
    p.add_argument("--redact-contributors", dest="redact_contributors", action="store_true", help=argparse.SUPPRESS)
    p.set_defaults(
        func=command_export_jsonl,
        raw_export_policy="full_redact",
        redact_paths=True,
        redact_contributors=True,
    )

    p = sub.add_parser("import-jsonl")
    p.add_argument("path")
    p.add_argument("--max-conflicts", type=int, default=0)
    p.add_argument(
        "--redact-raw",
        dest="redact_raw",
        action="store_true",
        help="redact imported raw source lines and keep only safe summary fields (default)",
    )
    p.add_argument(
        "--preserve-raw",
        dest="redact_raw",
        action="store_false",
        help="allow imported raw source lines when raw storage mode is full",
    )
    p.set_defaults(func=command_import_jsonl, redact_raw=True)

    p = sub.add_parser("backup")
    p.add_argument("--output")
    p.add_argument("--overwrite", action="store_true")
    p.set_defaults(func=command_backup)

    p = sub.add_parser("recover")
    p.add_argument("--backup-first", nargs="?", const=True, default=True, type=parse_bool_flag)
    p.add_argument("--no-backup-first", dest="backup_first", action="store_false")
    p.add_argument("--max-conflicts", type=int, default=999999)
    p.add_argument("--limit", type=int)
    p.set_defaults(func=command_recover)

    p = sub.add_parser("query")
    query_sub = p.add_subparsers(dest="query_name", required=True)
    add_query_common(query_sub.add_parser("never-pass"))
    query_sub.choices["never-pass"].add_argument("--pass", dest="pass_code", required=True)
    add_scope(query_sub.choices["never-pass"], default="current-eligible")
    add_query_common(query_sub.add_parser("pass-counts"))
    query_sub.choices["pass-counts"].add_argument("--path", required=True)
    query_sub.choices["pass-counts"].add_argument("--pass", dest="pass_code")
    add_query_common(query_sub.add_parser("file-history"))
    query_sub.choices["file-history"].add_argument("--path", required=True)
    add_query_common(query_sub.add_parser("regressions"))
    query_sub.choices["regressions"].add_argument("--path")
    add_query_common(query_sub.add_parser("least-reviewed"))
    add_scope(query_sub.choices["least-reviewed"], default="current-eligible")
    add_query_common(query_sub.add_parser("most-fragile"))
    add_scope(query_sub.choices["most-fragile"], default="current-eligible")
    add_query_common(query_sub.add_parser("changed-since-last-pass"))
    query_sub.choices["changed-since-last-pass"].add_argument("--pass", dest="pass_code", required=True)
    add_scope(query_sub.choices["changed-since-last-pass"], default="current-eligible")
    add_query_common(query_sub.add_parser("selection-candidates"))
    query_sub.choices["selection-candidates"].add_argument("--mode", default="oldest-mtime")
    add_query_common(query_sub.add_parser("explain-selection"))
    query_sub.choices["explain-selection"].add_argument("--cycle", dest="cycle_id")
    query_sub.choices["explain-selection"].add_argument("--path")
    p.set_defaults(func=command_query)

    p = sub.add_parser("mark-regression")
    p.add_argument("--path", required=True)
    p.add_argument("--cycle-id", default="")
    p.add_argument("--cause-commit", default="")
    p.add_argument("--reason", required=True)
    p.add_argument("--confidence", choices=["asserted", "inferred", "suspected"], default="asserted")
    p.add_argument("--status", choices=["active", "retracted", "superseded", "disputed"], default="active")
    p.add_argument("--detector", default="operator")
    p.add_argument("--source-kind", default="operator", choices=sorted(SOURCE_KINDS))
    p.set_defaults(func=command_mark_regression)

    p = sub.add_parser("prune")
    p.add_argument("--older-than-days", type=int)
    p.add_argument("--raw-only", action="store_true")
    p.add_argument("--transient-artifacts", action="store_true")
    p.add_argument("--scrub-transient-metadata", action="store_true")
    p.add_argument("--candidate-details", action="store_true")
    p.add_argument("--vacuum", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=command_prune)

    return parser


def add_cycle_args(parser: argparse.ArgumentParser, required: bool = True) -> None:
    parser.add_argument("--cycle-id", required=required, default="")
    parser.add_argument("--run-hash", required=required, default="")


def add_query_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--format", choices=["text", "json", "jsonl", "tsv"], default="text")
    parser.add_argument("--fail-on-no-match", action="store_true")


def add_scope(parser: argparse.ArgumentParser, default: str) -> None:
    parser.add_argument(
        "--scope",
        choices=["current-eligible", "current-tracked", "known-active", "all-known", "deleted", "selected-history"],
        default=default,
    )


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if getattr(args, "raw_repo_identity", False):
        os.environ[UPKEEPER_RAW_REPO_IDENTITY_ENV] = "1"
    try:
        return int(args.func(args))
    except LatticeCommandError as exc:
        if not exc.emitted:
            print(f"upkeeper_lattice: {exc}", file=sys.stderr)
        return int(exc.code)
    except sqlite3.IntegrityError as exc:
        print(f"upkeeper_lattice: integrity failure: {exc}", file=sys.stderr)
        return EXIT_INTEGRITY
    except sqlite3.Error as exc:
        print(f"upkeeper_lattice: database error: {exc}", file=sys.stderr)
        return EXIT_DB_UNAVAILABLE
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        redirect_stdout_to_devnull()
        raise SystemExit(EXIT_SUCCESS)
