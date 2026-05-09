#!/usr/bin/env python3
"""Upkeeper Lattice: local SQLite evidence ledger and query surface."""

from __future__ import annotations

import argparse
import hashlib
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
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 1

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
ALLOWED_OUTCOMES = {
    "planned",
    "not_applicable",
    "clean",
    "fixed",
    "blocked",
    "regression_found",
    "unknown",
}

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
      raw_ref text,
      raw_text text,
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
      status text,
      old_path text,
      head_blob text,
      worktree_hash text,
      size_bytes integer,
      mtime_epoch integer
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
    "CREATE INDEX IF NOT EXISTS idx_git_file_changes_repo_path_epoch ON git_file_changes(repo_id, path, change_epoch)",
    "CREATE INDEX IF NOT EXISTS idx_regression_events_repo_file_epoch ON regression_events(repo_id, file_id, marked_epoch)",
    "CREATE INDEX IF NOT EXISTS idx_extension_facts_lookup ON extension_facts(namespace, key, subject_type, subject_pk)",
    "CREATE INDEX IF NOT EXISTS idx_pass_run_attributes_lookup ON pass_run_attributes(file_pass_run_id, namespace, key)",
]


def epoch_now() -> int:
    return int(time.time())


def json_dumps(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, default=str)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_text(text: str) -> str:
    return sha256_bytes(text.encode("utf-8", "surrogateescape"))


def print_json(value: Any) -> None:
    print(json.dumps(value, sort_keys=True, indent=2))


def fail(message: str, code: int) -> None:
    print(f"upkeeper_lattice: {message}", file=sys.stderr)
    raise SystemExit(code)


def run_git(root: Path, args: list[str], *, text: bool = True, check: bool = True) -> Any:
    try:
        return subprocess.run(
            ["git", "-C", str(root), *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=text,
            check=check,
        )
    except FileNotFoundError:
        raise SystemExit(EXIT_GIT_UNAVAILABLE)
    except subprocess.CalledProcessError:
        if check:
            raise
        return None


def git_output(root: Path, args: list[str], default: str = "") -> str:
    try:
        result = run_git(root, args, text=True, check=True)
        return result.stdout.strip()
    except (subprocess.CalledProcessError, SystemExit):
        return default


def inside_git_repo(root: Path) -> bool:
    return git_output(root, ["rev-parse", "--is-inside-work-tree"]) == "true"


def default_root() -> Path:
    return Path(os.environ.get("UPKEEPER_ROOT", os.getcwd())).resolve()


def default_db_path(root: Path) -> Path:
    raw = os.environ.get("UPKEEPER_LATTICE_DB")
    if raw:
        return Path(raw).expanduser().resolve() if Path(raw).is_absolute() else (root / raw).resolve()
    return (root / "runtime/upkeeper-lattice/lattice.sqlite3").resolve()


def normalize_db_path(raw: str | None, root: Path) -> Path:
    if raw:
        path = Path(raw).expanduser()
        return path.resolve() if path.is_absolute() else (root / path).resolve()
    return default_db_path(root)


def path_under(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


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
            ["git", "-C", str(root), "check-ignore", "-q", "--", rel],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return result.returncode == 0
    except FileNotFoundError:
        return False


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
    except FileNotFoundError:
        return False


def db_side_paths(db_path: Path, journal_mode: str) -> list[Path]:
    side_paths = [db_path, db_path.with_name(db_path.name + "-journal")]
    if journal_mode.lower() == "wal":
        side_paths.extend([db_path.with_name(db_path.name + "-wal"), db_path.with_name(db_path.name + "-shm")])
    side_paths.extend([db_path.parent / "backups", db_path.parent / "exports", db_path.parent / "recovery"])
    return side_paths


def path_safety(root: Path, db_path: Path, journal_mode: str) -> dict[str, Any]:
    runtime_root = (root / "runtime").resolve()
    paths = db_side_paths(db_path, journal_mode)
    statuses = []
    unsafe = False
    for path in paths:
        under_runtime = path_under(path, runtime_root)
        tracked = git_path_tracked(root, path) if path_under(path, root) else False
        ignored = git_path_ignored(root, path) if path_under(path, root) else False
        explicit_ok = under_runtime or ignored
        item_unsafe = tracked or (path_under(path, root) and not explicit_ok)
        unsafe = unsafe or item_unsafe
        statuses.append(
            {
                "path": str(path),
                "under_runtime": under_runtime,
                "git_tracked": tracked,
                "git_ignored": ignored,
                "safe": not item_unsafe,
            }
        )
    return {"safe": not unsafe, "paths": statuses}


def check_path_safe(root: Path, db_path: Path, journal_mode: str, allow_unsafe: bool) -> None:
    safety = path_safety(root, db_path, journal_mode)
    if not safety["safe"] and not allow_unsafe:
        print_json({"status": "unsafe_db_path", "db_path": str(db_path), "path_safety": safety})
        raise SystemExit(EXIT_UNSAFE_DB_PATH)


def chmod_private(path: Path, is_dir: bool = False) -> None:
    try:
        path.chmod(0o700 if is_dir else 0o600)
    except OSError:
        pass


def connect(db_path: Path, journal_mode: str, *, create_parent: bool = False) -> sqlite3.Connection:
    if create_parent:
        db_path.parent.mkdir(parents=True, exist_ok=True)
        chmod_private(db_path.parent, is_dir=True)
    if not db_path.parent.exists():
        fail(f"DB parent directory does not exist: {db_path.parent}", EXIT_DB_UNAVAILABLE)
    try:
        conn = sqlite3.connect(str(db_path))
    except sqlite3.Error as exc:
        fail(f"DB unavailable: {exc}", EXIT_DB_UNAVAILABLE)
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
        fail(f"cannot set SQLite journal mode {requested}: {exc}", EXIT_DB_UNAVAILABLE)
    return conn


def table_columns(conn: sqlite3.Connection, table: str) -> list[str]:
    return [row["name"] for row in conn.execute(f"PRAGMA table_info({table})")]


def table_primary_key(conn: sqlite3.Connection, table: str) -> str | None:
    for row in conn.execute(f"PRAGMA table_info({table})"):
        if int(row["pk"] or 0) == 1:
            return str(row["name"])
    return None


def init_schema(conn: sqlite3.Connection, root: Path | None = None) -> None:
    now = epoch_now()
    with conn:
        for sql in CREATE_TABLE_SQL:
            conn.execute(sql)
        for sql in CREATE_INDEX_SQL:
            conn.execute(sql)
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
    install_pass_registry(conn, root or default_root())


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


def sanitize_remote_url(raw: str) -> str:
    if not raw:
        return ""
    return re.sub(r"(https?://)[^/@\s]+@", r"\1<redacted>@", raw)


def repo_git_info(root: Path) -> dict[str, str]:
    info = {
        "git_common_dir": git_output(root, ["rev-parse", "--git-common-dir"], ""),
        "head_sha": git_output(root, ["rev-parse", "--verify", "HEAD"], ""),
        "head_tree_sha": git_output(root, ["rev-parse", "HEAD^{tree}"], ""),
        "branch_name": git_output(root, ["branch", "--show-current"], ""),
        "remote_url": sanitize_remote_url(git_output(root, ["config", "--get", "remote.origin.url"], "")),
    }
    return info


def ensure_repository(conn: sqlite3.Connection, root: Path) -> int:
    now = epoch_now()
    root = root.resolve()
    info = repo_git_info(root)
    common = info["git_common_dir"]
    repo_key_src = f"{root}|{common}|{info['remote_url']}"
    repo_key = sha256_text(repo_key_src)
    origin_hash = sha256_text(info["remote_url"]) if info["remote_url"] else ""
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
                str(root),
                str(root),
                common,
                info["head_sha"],
                info["head_tree_sha"],
                info["branch_name"],
                info["remote_url"],
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
                str(root),
                str(root),
                str(root),
                str(root),
                common,
                info["head_sha"],
                info["head_tree_sha"],
                info["branch_name"],
                info["remote_url"],
                origin_hash,
                now,
                now,
            ),
        )
        repo_id = int(cur.lastrowid)
    for kind, value in [
        ("root_path", str(root)),
        ("repo_key", repo_key),
        ("git_common_dir", common),
        ("remote_url_hash", origin_hash),
    ]:
        if not value:
            continue
        conn.execute(
            """
            insert into repo_aliases(repo_id, alias_kind, alias_value, first_seen_epoch, last_seen_epoch)
            values (?, ?, ?, ?, ?)
            on conflict(alias_kind, alias_value) do update set
              repo_id=excluded.repo_id,
              last_seen_epoch=excluded.last_seen_epoch
            """,
            (repo_id, kind, value, now, now),
        )
    return repo_id


def ensure_source_record(
    conn: sqlite3.Connection,
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
) -> int:
    if source_kind not in SOURCE_KINDS:
        source_kind = "operator"
    now = epoch_now()
    cur = conn.execute(
        """
        insert into source_records(
          repo_id, source_kind, source_path, source_uri, source_epoch, imported_epoch,
          raw_ref, raw_text, parsed_json, parse_status, fact_confidence
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            repo_id,
            source_kind,
            source_path or None,
            source_uri or None,
            source_epoch,
            now,
            raw_ref or None,
            raw_text,
            json_dumps(parsed) if parsed is not None else None,
            parse_status,
            fact_confidence,
        ),
    )
    return int(cur.lastrowid)


def ensure_file(
    conn: sqlite3.Connection,
    repo_id: int,
    path: str,
    *,
    canonical_path: str | None = None,
    state: str = "active",
    source_id: int | None = None,
) -> int:
    now = epoch_now()
    path = normalize_rel_path(path)
    canonical = normalize_rel_path(canonical_path or path)
    if not path:
        raise ValueError("empty path")
    row = conn.execute(
        "select file_id from files where repo_id=? and canonical_path=?",
        (repo_id, canonical),
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


def normalize_rel_path(path: str) -> str:
    path = path.strip()
    if not path:
        return ""
    path = path.replace("\\", "/")
    path = re.sub(r"^\./+", "", path)
    while "//" in path:
        path = path.replace("//", "/")
    return path


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
        if key in table_columns(conn, "cycles") and key not in columns:
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


def install_pass_registry(conn: sqlite3.Connection, root: Path) -> None:
    now = epoch_now()
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(
            conn,
            repo_id,
            "wrapper_observed",
            raw_ref="pass_registry",
            parsed={"passes": PASS_REGISTRY},
            parse_status="registry",
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
            path,
            confidence,
            json_dumps(details) if details is not None else None,
        ),
    )


def live_file_metadata(root: Path, rel_path: str) -> dict[str, Any]:
    rel_path = normalize_rel_path(rel_path)
    path = root / rel_path
    meta: dict[str, Any] = {"path": rel_path}
    try:
        st = path.stat()
        meta["mtime_epoch"] = int(st.st_mtime)
        meta["size_bytes"] = int(st.st_size)
        meta["executable"] = 1 if st.st_mode & 0o111 else 0
        meta["is_regular"] = 1 if stat.S_ISREG(st.st_mode) else 0
    except OSError:
        meta.update({"mtime_epoch": None, "size_bytes": None, "executable": None, "is_regular": 0})
    status = git_output(root, ["status", "--porcelain=v1", "--", rel_path], "")
    meta["git_status"] = status[:2].replace(" ", "_") if status else "clean"
    meta["worktree_hash"] = git_output(root, ["hash-object", "--", rel_path], "missing")
    meta["head_blob"] = git_output(root, ["rev-parse", f"HEAD:{rel_path}"], "none")
    if meta["head_blob"] == "none":
        meta["content_state"] = "untracked"
    elif meta["head_blob"] == meta["worktree_hash"]:
        meta["content_state"] = "matches_head"
    else:
        meta["content_state"] = "differs_from_head"
    meta["ignored"] = 1 if git_path_ignored(root, path) else 0
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
    cur = conn.execute(
        """
        insert into file_snapshots(
          file_id, repo_id, path, observed_epoch, source_id, git_status, content_state,
          head_blob, worktree_hash, mtime_epoch, size_bytes, executable, ignored, generated, test_path
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            file_id,
            repo_id,
            rel_path,
            observed_epoch or epoch_now(),
            source_id,
            meta.get("git_status"),
            meta.get("content_state"),
            meta.get("head_blob"),
            meta.get("worktree_hash"),
            meta.get("mtime_epoch"),
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
                rows.append({"path": raw, "candidate_state": "excluded", "exclusion_reason": "malformed_candidate_json"})
                continue
            if isinstance(obj, dict):
                rows.append(obj)
    return rows


def is_test_path(path: str) -> bool:
    parts = path.split("/")
    name = parts[-1]
    return any(part in TEST_DIRS for part in parts) or name.startswith("test_") or name.endswith("_test.py")


def is_text_file(path: Path) -> bool:
    try:
        return b"\0" not in path.read_bytes()[:4096]
    except OSError:
        return False


def live_candidate_paths(root: Path) -> list[dict[str, Any]]:
    if inside_git_repo(root):
        raw = subprocess.check_output(["git", "-C", str(root), "ls-files", "-co", "--exclude-standard", "-z"])
        paths = [p for p in raw.decode("utf-8", "surrogateescape").split("\0") if p]
    else:
        paths = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [name for name in dirnames if name not in {".git", "runtime"}]
            for filename in filenames:
                rel = repo_rel_path(root, Path(dirpath) / filename)
                if rel:
                    paths.append(rel)
    rows = []
    for rel in paths:
        reason = ""
        state = "eligible"
        p = root / rel
        if rel == "Upkeeper.log":
            reason = "excluded_exact"
        elif rel.startswith(".git/") or rel.startswith("runtime/"):
            reason = "excluded_prefix"
        elif is_test_path(rel):
            reason = "test_path"
        else:
            try:
                st = p.stat()
            except OSError:
                reason = "missing_at_stat"
            else:
                if not stat.S_ISREG(st.st_mode):
                    reason = "not_regular_file"
                else:
                    name = p.name
                    ext = p.suffix.lower()
                    candidate = name in BUILD_NAMES or ext in SCRIPT_EXTS
                    if not candidate and st.st_mode & 0o111:
                        candidate = is_text_file(p)
                        if not candidate:
                            reason = "executable_not_text"
                    if not candidate and not reason:
                        reason = "unsupported_extension"
        if reason:
            state = "excluded"
        meta = live_file_metadata(root, rel)
        rows.append(
            {
                "path": rel,
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
        if not inside_git_repo(root):
            return []
        raw = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"])
        return sorted(p for p in raw.decode("utf-8", "surrogateescape").split("\0") if p)
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
            print("\t".join("" if row.get(k) is None else str(row.get(k)) for k in keys))
    else:
        if not rows:
            return
        keys = list(rows[0].keys())
        widths = {key: max(len(key), *(len(str(row.get(key, ""))) for row in rows)) for key in keys}
        print("  ".join(key.ljust(widths[key]) for key in keys))
        for row in rows:
            print("  ".join(str(row.get(key, "") if row.get(key) is not None else "").ljust(widths[key]) for key in keys))


def command_init(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    db_path = normalize_db_path(args.db, root)
    journal_mode = args.journal_mode
    check_path_safe(root, db_path, journal_mode, args.allow_unsafe_db)
    conn = connect(db_path, journal_mode, create_parent=True)
    try:
        init_schema(conn, root)
        chmod_private(db_path)
    finally:
        conn.close()
    print_json({"status": "ok", "schema_version": SCHEMA_VERSION, "db_path": str(db_path)})
    return EXIT_SUCCESS


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
    if not db_path.parent.exists():
        result["status"] = "db_unavailable"
        return result, EXIT_DB_UNAVAILABLE
    conn = connect(db_path, journal_mode)
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
        meta = conn.execute("select value from schema_meta where key='schema_version'").fetchone()
        result["checks"]["schema_meta_version"] = meta["value"] if meta else None
        if not meta or str(meta["value"]) != str(SCHEMA_VERSION) or user_version != SCHEMA_VERSION:
            result["status"] = "schema_mismatch"
            return result, EXIT_SCHEMA_MISMATCH
        table_names = {row["name"] for row in conn.execute("select name from sqlite_master where type='table'")}
        missing_tables = [table for table in REQUIRED_TABLES if table not in table_names]
        result["checks"]["required_tables_missing"] = missing_tables
        index_names = {row["name"] for row in conn.execute("select name from sqlite_master where type='index'")}
        missing_indexes = [index for index in REQUIRED_INDEXES if index not in index_names]
        result["checks"]["required_indexes_missing"] = missing_indexes
        if missing_tables or missing_indexes:
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
            backup_path = create_backup(conn, db_path, output=args.backup_output)
            result["checks"]["backup_path"] = str(backup_path)
            result["checks"]["backup_created"] = backup_path.exists()
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
    conn = connect(db_path, args.journal_mode)
    ensure_schema(conn)
    with conn:
        repo_id = ensure_repository(conn, root)
        parsed = vars(args).copy()
        parsed.pop("func", None)
        source_id = ensure_source_record(conn, repo_id, "wrapper_observed", raw_ref="cycle_start", parsed=parsed)
        worktree_dirty = 1 if int(args.dirty_path_count or 0) > 0 else 0
        cycle_pk = ensure_cycle(
            conn,
            repo_id,
            args.cycle_id,
            args.run_hash,
            source_id=source_id,
            start_epoch=args.start_epoch or epoch_now(),
            execution_origin=args.execution_origin,
            model=args.model,
            effort=args.effort,
            mode=args.mode,
            config_file=args.config_file,
            branch_name=args.branch_name or repo_git_info(root)["branch_name"],
            head_sha=args.head_sha or repo_git_info(root)["head_sha"],
            head_tree_sha=args.head_tree_sha or repo_git_info(root)["head_tree_sha"],
            upstream_ref=args.upstream_ref,
            worktree_dirty=worktree_dirty,
            dry_run=parse_bool_int(str(args.dry_run)),
        )
        record_cycle_link_from_env(conn, repo_id, cycle_pk, args, source_id)
        record_worktree_snapshot(conn, root, repo_id, cycle_pk, "before_codex", source_id=source_id)
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
) -> int:
    observed = epoch_now()
    head_sha = git_output(root, ["rev-parse", "--verify", "HEAD"], "")
    branch = git_output(root, ["branch", "--show-current"], "")
    raw = b""
    try:
        raw = subprocess.check_output(["git", "-C", str(root), "status", "--porcelain=v1", "-z", "--untracked-files=all"])
    except (OSError, subprocess.CalledProcessError):
        raw = b""
    parts = raw.decode("utf-8", "surrogateescape").split("\0") if raw else []
    entries: list[tuple[str, str, str | None]] = []
    i = 0
    tracked = 0
    untracked = 0
    while i < len(parts):
        item = parts[i]
        i += 1
        if not item or len(item) < 4:
            continue
        status_code = item[:2]
        path = item[3:]
        old_path = None
        if status_code[0] in {"R", "C"} or status_code[1] in {"R", "C"}:
            if i < len(parts):
                old_path = parts[i] or None
                i += 1
        entries.append((status_code, path, old_path))
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
            json_dumps({"source": "git status --porcelain=v1 -z --untracked-files=all"}),
        ),
    )
    snapshot_id = int(cur.lastrowid)
    for status_code, path, old_path in entries:
        file_id = ensure_file(conn, repo_id, path, state="active", source_id=source_id)
        meta = live_file_metadata(root, path)
        conn.execute(
            """
            insert into worktree_snapshot_paths(
              worktree_snapshot_id, file_id, path, status, old_path, head_blob, worktree_hash, size_bytes, mtime_epoch
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                snapshot_id,
                file_id,
                path,
                status_code,
                old_path,
                meta.get("head_blob"),
                meta.get("worktree_hash"),
                meta.get("size_bytes"),
                meta.get("mtime_epoch"),
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
    return {str(row["path"]): row for row in rows}


def record_worktree_delta_events(
    conn: sqlite3.Connection,
    *,
    repo_id: int,
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
    before_paths = worktree_snapshot_path_map(conn, before_snapshot_id)
    after_paths = worktree_snapshot_path_map(conn, after_snapshot_id)

    all_paths = sorted(set(before_paths) | set(after_paths))
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
            },
        )


def command_record_worktree_snapshot(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    conn = connect(normalize_db_path(args.db, root), args.journal_mode)
    ensure_schema(conn)
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(conn, repo_id, "wrapper_observed", raw_ref=f"worktree_snapshot:{args.snapshot_kind}")
        cycle_pk = None
        if args.cycle_id and args.run_hash:
            cycle_pk = ensure_cycle(conn, repo_id, args.cycle_id, args.run_hash, source_id=source_id)
        snapshot_id = record_worktree_snapshot(conn, root, repo_id, cycle_pk, args.snapshot_kind, source_id=source_id)
    print_json({"status": "ok", "worktree_snapshot_id": snapshot_id})
    return EXIT_SUCCESS


def command_record_preselect(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    conn = connect(normalize_db_path(args.db, root), args.journal_mode)
    ensure_schema(conn)
    selection = parse_key_value_file(Path(args.selection_file)) if args.selection_file else parse_key_value_text(sys.stdin.read())
    candidate_rows = load_jsonl(Path(args.candidate_file)) if args.candidate_file else []
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(
            conn,
            repo_id,
            "wrapper_observed",
            raw_ref="preselect",
            raw_text=json_dumps(selection),
            parsed={"selection": selection, "candidate_count": len(candidate_rows)},
        )
        cycle_pk = ensure_cycle(conn, repo_id, args.cycle_id, args.run_hash, source_id=source_id)
        selected_path = normalize_rel_path(selection.get("path", ""))
        selected_file_id = ensure_file(conn, repo_id, selected_path, source_id=source_id) if selected_path else None
        mode = selection.get("selection_mode", "unknown")
        gate = selector_priority_gate(mode)
        selected_rank = None
        eligible_count = int(selection.get("eligible_count") or 0)
        excluded_count = 0
        for index, row in enumerate(candidate_rows, start=1):
            if row.get("candidate_state") == "excluded":
                excluded_count += 1
            if normalize_rel_path(str(row.get("path", ""))) == selected_path:
                selected_rank = int(row.get("rank") or index)
        if selected_rank is None and selected_path:
            selected_rank = 1
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
                eligible_count or len([r for r in candidate_rows if r.get("candidate_state") in {"eligible", "selected"}]),
                excluded_count,
                0,
                None,
                selected_file_id,
                selected_path or None,
                selected_rank,
                json_dumps(selection),
            ),
        )
        selection_run_id = int(cur.lastrowid)
        if candidate_rows:
            for index, row in enumerate(candidate_rows, start=1):
                path = normalize_rel_path(str(row.get("path", "")))
                if not path:
                    continue
                state = str(row.get("candidate_state", "eligible"))
                if path == selected_path:
                    state = "selected"
                file_id = ensure_file(conn, repo_id, path, source_id=source_id) if state != "forced_missing" else None
                rank = row.get("rank")
                if state in {"eligible", "selected"} and rank is None:
                    rank = index
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
                        path,
                        state,
                        rank,
                        row.get("mtime_epoch"),
                        row.get("git_status"),
                        row.get("content_state"),
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
                    selected_path,
                    int(selection.get("epoch") or 0) or None,
                    selection.get("git_status"),
                    selection.get("content_state"),
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
                (selected_file_id, selected_path, selection.get("selection_basis"), cycle_pk),
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
    print_json({"status": "ok", "selection_run_id": selection_run_id, "selected_path": selected_path})
    return EXIT_SUCCESS


def parse_review_summary_file(path: Path) -> dict[str, str]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}
    outcome = ""
    for match in re.finditer(r"\b(REVIEWED_AND_FIXED|REVIEWED_CLEAN|STOPPED_ON_BLOCKER)\b", text):
        outcome = match.group(1)
        break
    selected_file = ""
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not re.search(r"\b(selected|target|review target)\b", line, re.I):
            continue
        if not re.search(r"\b(file|target)\b", line, re.I):
            continue
        md = re.search(r"\]\(([^)]+)\)", line)
        bt = re.search(r"`([^`]+)`", line)
        if md:
            selected_file = md.group(1).strip("<>").split(":", 1)[0]
        elif bt:
            selected_file = bt.group(1)
        elif ":" in line:
            selected_file = line.split(":", 1)[1].strip()
        if selected_file:
            break
    return {"review_outcome": outcome, "selected_file": selected_file}


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
    details = {
        "before_snapshot_id": before["snapshot_id"],
        "after_snapshot_id": after["snapshot_id"],
        "before_worktree_hash": before_hash,
        "after_worktree_hash": after_hash,
        "before_mtime_epoch": before_mtime,
        "after_mtime_epoch": after_mtime,
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
    repo_id: int,
    *,
    cycle_pk: int | None,
    source_id: int | None,
    artifact_kind: str,
    path: str,
    details: Any = None,
) -> None:
    if not path:
        return
    p = Path(path)
    exists = p.exists()
    size = None
    digest = None
    if exists and p.is_file():
        try:
            data = p.read_bytes()
            size = len(data)
            digest = sha256_bytes(data)
        except OSError:
            pass
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
            path,
            1 if exists else 0,
            size,
            digest,
            epoch_now(),
            1 if exists else 0,
            json_dumps(details) if details is not None else None,
        ),
    )


def command_record_cycle_finish(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    conn = connect(normalize_db_path(args.db, root), args.journal_mode)
    ensure_schema(conn)
    with conn:
        repo_id = ensure_repository(conn, root)
        parsed = vars(args).copy()
        parsed.pop("func", None)
        review = parse_review_summary_file(Path(args.last_message_file)) if args.last_message_file else {}
        review_outcome = args.review_outcome or review.get("review_outcome") or None
        reported_selected = normalize_rel_path(args.review_selected_path or review.get("selected_file", ""))
        source_id = ensure_source_record(conn, repo_id, "wrapper_observed", raw_ref="cycle_finish", parsed=parsed)
        cycle_pk = ensure_cycle(conn, repo_id, args.cycle_id, args.run_hash, source_id=source_id)
        selected_path = normalize_rel_path(args.selected_path or "")
        selected_file_id = ensure_file(conn, repo_id, selected_path, source_id=source_id) if selected_path else None
        if reported_selected and selected_path and reported_selected != selected_path:
            replacement_id = ensure_file(conn, repo_id, reported_selected, source_id=source_id)
            record_file_event(
                conn,
                repo_id,
                "target_substituted",
                file_id=replacement_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                path=reported_selected,
                confidence="reported",
                details={"preselected_path": selected_path, "reported_selected_path": reported_selected},
            )
        conn.execute(
            """
            update cycles set
              end_epoch=?, status_marker=?, review_outcome=?, codex_exit=?, wrapper_exit=?,
              finish_reason=?, finish_level=?, codex_exec_started=?, dry_run=?,
              selected_file_id=coalesce(?, selected_file_id),
              selected_path=coalesce(?, selected_path)
            where cycle_pk=?
            """,
            (
                args.end_epoch or epoch_now(),
                args.status_marker or None,
                review_outcome,
                args.codex_exit,
                args.wrapper_exit,
                args.finish_reason,
                args.finish_level,
                args.codex_exec_started,
                parse_bool_int(str(args.dry_run)),
                selected_file_id,
                selected_path or None,
                cycle_pk,
            ),
        )
        snapshot_id = record_worktree_snapshot(conn, root, repo_id, cycle_pk, args.snapshot_kind, source_id=source_id)
        record_worktree_delta_events(
            conn,
            repo_id=repo_id,
            cycle_pk=cycle_pk,
            source_id=source_id,
            after_snapshot_id=snapshot_id,
        )
        if selected_path:
            after_snapshot_id = insert_file_snapshot(conn, root, repo_id, selected_path, file_id=selected_file_id, source_id=source_id)
            record_file_event(
                conn,
                repo_id,
                "snapshot_after",
                file_id=selected_file_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                path=selected_path,
                details={"snapshot_id": after_snapshot_id},
            )
            record_selected_file_delta(
                conn,
                repo_id=repo_id,
                cycle_pk=cycle_pk,
                file_id=selected_file_id,
                source_id=source_id,
                path=selected_path,
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
                repo_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                artifact_kind=artifact_kind,
                path=artifact_path or "",
            )
    print_json({"status": "ok", "cycle_pk": cycle_pk, "worktree_snapshot_id": snapshot_id})
    return EXIT_SUCCESS


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
            rejected.append({"raw_line": raw_line, "line_number": line_number, "reason": "malformed_token"})
            continue
        if duplicate:
            rejected.append({"raw_line": raw_line, "line_number": line_number, "reason": f"duplicate_key:{duplicate}"})
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
    raw_line: str = "",
    confidence: str = "reported",
    attributes: dict[str, Any] | None = None,
) -> int:
    pass_id = ensure_pass(conn, pass_code)
    file_id = ensure_file(conn, repo_id, path, source_id=source_id)
    attempted = 1 if outcome not in {"planned", "unknown"} else 0
    cur = conn.execute(
        """
        insert into file_pass_runs(
          repo_id, file_id, cycle_pk, pass_id, pass_code, planned, applicable,
          attempted, outcome, changed, regression, confidence, source_id, raw_line, created_epoch
        ) values (?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            repo_id,
            file_id,
            cycle_pk,
            pass_id,
            normalize_pass_code(pass_code),
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
    conn = connect(normalize_db_path(args.db, root), args.journal_mode)
    ensure_schema(conn)
    recorded = 0
    rejected_count = 0
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(
            conn,
            repo_id,
            "transcript" if args.from_file else "wrapper_observed",
            source_path=args.from_file or "",
            raw_ref="pass_result",
            parsed=vars(args),
        )
        cycle_pk = None
        if args.cycle_id and args.run_hash:
            cycle_pk = ensure_cycle(conn, repo_id, args.cycle_id, args.run_hash, source_id=source_id)
        planned = split_csv(args.planned_passes)
        planned.extend(args.planned_pass or [])
        seen: set[tuple[str, str]] = set()
        if args.from_file:
            accepted, rejected = parse_pass_result_lines(Path(args.from_file))
            rejected_count = len(rejected)
            for item in rejected:
                ensure_source_record(
                    conn,
                    repo_id,
                    "transcript",
                    source_path=args.from_file,
                    raw_ref=f"pass_result_rejected:{item.get('line_number')}",
                    raw_text=item.get("raw_line", ""),
                    parsed=item,
                    parse_status="rejected",
                    fact_confidence="rejected",
                )
            for item in accepted:
                pass_code = normalize_pass_code(item["pass"])
                path = normalize_rel_path(item["file"])
                applicable = parse_bool_int(item.get("applicable"))
                changed = parse_bool_int(item.get("changed"))
                regression = parse_bool_int(item.get("regression"))
                outcome = item.get("outcome", "unknown")
                attrs = {k: v for k, v in item.items() if k not in {"pass", "file", "applicable", "outcome", "changed", "regression", "raw_line", "line_number"}}
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
                    raw_line=item.get("raw_line", ""),
                    attributes=attrs,
                )
                seen.add((pass_code, path))
                recorded += 1
        elif args.pass_code and args.path:
            pass_code = normalize_pass_code(args.pass_code)
            path = normalize_rel_path(args.path)
            attrs = parse_attribute_args(args.attribute)
            record_one_pass_result(
                conn,
                root,
                repo_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                pass_code=pass_code,
                path=path,
                applicable=parse_bool_int(args.applicable),
                outcome=args.outcome,
                changed=parse_bool_int(args.changed),
                regression=parse_bool_int(args.regression),
                raw_line=args.raw_line or "",
                attributes=attrs,
            )
            seen.add((pass_code, path))
            recorded += 1
        target_path = normalize_rel_path(args.path or args.selected_path or "")
        for raw_pass in planned:
            pass_code = normalize_pass_code(raw_pass)
            if not target_path or (pass_code, target_path) in seen:
                continue
            record_one_pass_result(
                conn,
                root,
                repo_id,
                cycle_pk=cycle_pk,
                source_id=source_id,
                pass_code=pass_code,
                path=target_path,
                applicable=None,
                outcome="unknown",
                changed=None,
                regression=None,
                raw_line="",
                confidence="missing_marker",
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


def refresh_rollups(conn: sqlite3.Connection, repo_id: int) -> None:
    now = epoch_now()
    file_ids = [int(row["file_id"]) for row in conn.execute("select file_id from files where repo_id=?", (repo_id,))]
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


def ensure_contributor(conn: sqlite3.Connection, name: str, email: str) -> int | None:
    if not name and not email:
        return None
    conn.execute(
        "insert or ignore into contributors(name, email) values (?, ?)",
        (name or None, email or None),
    )
    row = conn.execute(
        "select contributor_id from contributors where name is ? and email is ?",
        (name or None, email or None),
    ).fetchone()
    if row:
        return int(row["contributor_id"])
    row = conn.execute(
        "select contributor_id from contributors where coalesce(name,'')=? and coalesce(email,'')=?",
        (name, email),
    ).fetchone()
    return int(row["contributor_id"]) if row else None


def command_import_git(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    if not inside_git_repo(root):
        print_json({"status": "unavailable", "reason": "no_git_repository"})
        return EXIT_GIT_UNAVAILABLE
    conn = connect(normalize_db_path(args.db, root), args.journal_mode)
    ensure_schema(conn)
    rows_seen = 0
    rows_written = 0
    with conn:
        repo_id = ensure_repository(conn, root)
        import_id = start_import(conn, repo_id, "local_git", {"root": str(root)})
        source_id = ensure_source_record(conn, repo_id, "local_git", raw_ref="git-import", parse_status="started")
        try:
            revs = subprocess.check_output(["git", "-C", str(root), "rev-list", "--all", "--reverse"], text=True)
        except subprocess.CalledProcessError:
            finish_import(conn, import_id, "unavailable", rows_seen, rows_written, 0, {"reason": "git_rev_list_failed"})
            print_json({"status": "unavailable", "reason": "git_rev_list_failed"})
            return EXIT_GIT_UNAVAILABLE
        shas = [line.strip() for line in revs.splitlines() if line.strip()]
        if args.limit:
            shas = shas[-int(args.limit) :]
        for sha in shas:
            rows_seen += 1
            try:
                raw = subprocess.check_output(
                    [
                        "git",
                        "-C",
                        str(root),
                        "show",
                        "--format=%H%x00%an%x00%ae%x00%at%x00%cn%x00%ce%x00%ct%x00%s%x00",
                        "--name-status",
                        "--find-renames",
                        "-z",
                        sha,
                    ]
                )
            except subprocess.CalledProcessError:
                continue
            parts = raw.decode("utf-8", "surrogateescape").split("\0")
            if len(parts) < 8:
                continue
            commit_sha, an, ae, at, cn, ce, ct, subject = parts[:8]
            author_id = ensure_contributor(conn, an, ae)
            committer_id = ensure_contributor(conn, cn, ce)
            commit_source_id = ensure_source_record(
                conn,
                repo_id,
                "local_git",
                raw_ref=commit_sha,
                parsed={"subject": subject},
                source_epoch=int(at or 0) if str(at).isdigit() else None,
                parse_status="parsed",
            )
            conn.execute(
                """
                insert or ignore into git_commits(
                  repo_id, sha, author_id, committer_id, author_epoch, committer_epoch, subject, source_id
                ) values (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    repo_id,
                    commit_sha,
                    author_id,
                    committer_id,
                    int(at or 0) if str(at).isdigit() else None,
                    int(ct or 0) if str(ct).isdigit() else None,
                    subject,
                    commit_source_id,
                ),
            )
            commit_row = conn.execute(
                "select commit_id from git_commits where repo_id=? and sha=?",
                (repo_id, commit_sha),
            ).fetchone()
            if not commit_row:
                continue
            commit_id = int(commit_row["commit_id"])
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
                state = "deleted" if status_code.startswith("D") else ("renamed" if status_code.startswith("R") else "active")
                file_id = ensure_file(conn, repo_id, path, canonical_path=canonical, state=state, source_id=commit_source_id)
                conn.execute(
                    """
                    insert into git_file_changes(
                      repo_id, commit_id, file_id, status, path, old_path, additions, deletions, change_epoch, source_id
                    ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        repo_id,
                        commit_id,
                        file_id,
                        status_code,
                        path,
                        old_path,
                        None,
                        None,
                        int(at or 0) if str(at).isdigit() else None,
                        commit_source_id,
                    ),
                )
                rows_written += 1
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
        finish_import(conn, import_id, "ok", rows_seen, rows_written, 0, {"shallow": shallow})
    print_json({"status": "ok", "commits_seen": rows_seen, "file_changes_written": rows_written})
    return EXIT_SUCCESS


def start_import(conn: sqlite3.Connection, repo_id: int, import_kind: str, details: Any = None) -> int:
    cur = conn.execute(
        """
        insert into lattice_imports(repo_id, import_kind, started_epoch, status, rows_seen, rows_written, conflicts, details_json)
        values (?, ?, ?, 'started', 0, 0, 0, ?)
        """,
        (repo_id, import_kind, epoch_now(), json_dumps(details) if details is not None else None),
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


def command_import_upkeeper_log(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    log_path = Path(args.path or root / "Upkeeper.log")
    conn = connect(normalize_db_path(args.db, root), args.journal_mode)
    ensure_schema(conn)
    rows_seen = rows_written = 0
    with conn:
        repo_id = ensure_repository(conn, root)
        import_id = start_import(conn, repo_id, "upkeeper_log", {"path": str(log_path)})
        if not log_path.exists():
            finish_import(conn, import_id, "unavailable", 0, 0, 0, {"reason": "missing_log"})
            print_json({"status": "unavailable", "reason": "missing_log", "path": str(log_path)})
            return EXIT_SUCCESS
        for raw_line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
            rows_seen += 1
            parsed = parse_upkeeper_log_line(raw_line)
            if not parsed:
                continue
            source_id = ensure_source_record(
                conn,
                repo_id,
                "upkeeper_log",
                source_path=str(log_path),
                raw_ref=parsed.get("event", ""),
                raw_text=raw_line if args.raw else None,
                parsed=parsed,
                parse_status="parsed",
            )
            cycle_id = str(parsed.get("cycle", ""))
            run_hash = str(parsed.get("run_hash", ""))
            event = str(parsed.get("event", ""))
            if cycle_id and run_hash:
                cycle_pk = ensure_cycle(conn, repo_id, cycle_id, run_hash, source_id=source_id)
                if event == "cycle.start":
                    ensure_cycle(
                        conn,
                        repo_id,
                        cycle_id,
                        run_hash,
                        source_id=source_id,
                        execution_origin=parsed.get("execution_origin"),
                        model=parsed.get("model"),
                        effort=parsed.get("effort"),
                        mode=parsed.get("mode"),
                        config_file=parsed.get("config_file"),
                        worktree_dirty=1 if str(parsed.get("dirty_paths", "0")).isdigit() and int(parsed.get("dirty_paths", "0")) > 0 else 0,
                        dry_run=parse_bool_int(str(parsed.get("dry_run", ""))),
                    )
                elif event == "review.preselect":
                    selected_path = normalize_rel_path(str(parsed.get("path", "")))
                    file_id = ensure_file(conn, repo_id, selected_path, source_id=source_id) if selected_path else None
                    conn.execute(
                        "update cycles set selected_file_id=?, selected_path=?, selection_basis=? where cycle_pk=?",
                        (file_id, selected_path or None, parsed.get("basis"), cycle_pk),
                    )
                elif event == "cycle.summary":
                    conn.execute(
                        "update cycles set status_marker=?, codex_exit=? where cycle_pk=?",
                        (parsed.get("status_marker"), int(parsed["codex_exit"]) if str(parsed.get("codex_exit", "")).lstrip("-").isdigit() else None, cycle_pk),
                    )
                elif event == "cycle.exit":
                    conn.execute(
                        "update cycles set wrapper_exit=?, finish_reason=? where cycle_pk=?",
                        (int(parsed["exit_code"]) if str(parsed.get("exit_code", "")).lstrip("-").isdigit() else None, parsed.get("reason"), cycle_pk),
                    )
            rows_written += 1
        finish_import(conn, import_id, "ok", rows_seen, rows_written, 0, {"path": str(log_path)})
    print_json({"status": "ok", "rows_seen": rows_seen, "rows_written": rows_written})
    return EXIT_SUCCESS


def command_import_change_notes(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    paths = [Path(p) for p in args.paths] if args.paths else sorted(root.glob("change_notes_*.md"))
    conn = connect(normalize_db_path(args.db, root), args.journal_mode)
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
                    repo_id,
                    "change_notes",
                    source_path=str(path),
                    raw_ref=f"{current_version}:{line_number}",
                    raw_text=raw if args.raw else None,
                    parsed={"version": current_version, "date": current_date, "item_number": int(item.group(1)), "text": text},
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
                    if "/" not in ref and ref not in {"Upkeeper", "README.md", "AGENTS.md"}:
                        continue
                    try:
                        file_id = ensure_file(conn, repo_id, ref, source_id=source_id)
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


def export_table_rows(conn: sqlite3.Connection, table: str) -> Iterable[dict[str, Any]]:
    columns = table_columns(conn, table)
    if not columns:
        return []
    pk = table_primary_key(conn, table)
    order = pk or columns[0]
    return (dict(row) for row in conn.execute(f"select * from {table} order by {order}"))


def redact_payload(payload: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    redacted = dict(payload)
    if args.redact_raw:
        for key in ("raw_text", "details_json", "parsed_json"):
            if key in redacted and redacted[key] is not None:
                redacted[key] = "<redacted>"
    if args.redact_paths:
        for key in ("root_path", "first_seen_root_path", "current_root_path", "working_tree_path", "source_path", "path", "old_path", "current_path", "canonical_path", "output_path"):
            if key in redacted and redacted[key] is not None:
                redacted[key] = "path-sha256:" + sha256_text(str(redacted[key]))
    if args.redact_contributors:
        for key in ("name", "email", "github_login"):
            if key in redacted and redacted[key] is not None:
                redacted[key] = "<redacted>"
    return redacted


def command_export_jsonl(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    db_path = normalize_db_path(args.db, root)
    conn = connect(db_path, args.journal_mode)
    ensure_schema(conn)
    repo_id = ensure_repository(conn, root)
    output = Path(args.output) if args.output else db_path.parent / "exports" / f"lattice-export-{epoch_now()}.jsonl"
    output.parent.mkdir(parents=True, exist_ok=True)
    chmod_private(output.parent, is_dir=True)
    started = epoch_now()
    row_count = 0
    with conn, tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=str(output.parent), delete=False) as handle:
        temp_path = Path(handle.name)
        for table in REQUIRED_TABLES:
            if table.startswith("file_") and table.endswith("_rollups"):
                continue
            for payload in export_table_rows(conn, table):
                payload = redact_payload(payload, args)
                pk = table_primary_key(conn, table)
                logical = f"{table}:{payload.get(pk) if pk else sha256_text(json_dumps(payload))}"
                payload_hash = sha256_text(json_dumps(payload))
                row = {
                    "schema_version": SCHEMA_VERSION,
                    "row_type": table,
                    "row_version": 1,
                    "logical_key": logical,
                    "source_identity": {
                        "db_path_hash": sha256_text(str(db_path)),
                    },
                    "repo_identity": {
                        "repo_id": repo_id,
                        "root_path": str(root) if not args.redact_paths else "path-sha256:" + sha256_text(str(root)),
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
        source_id = ensure_source_record(conn, repo_id, "lattice_export", source_path=str(output), raw_ref=digest, parsed={"row_count": row_count})
        record_file_event(conn, repo_id, "export_written", source_id=source_id, path=str(output), details={"row_count": row_count, "sha256": digest})
    print_json({"status": "ok", "output_path": str(output), "row_count": row_count, "sha256": digest})
    return EXIT_SUCCESS


def command_import_jsonl(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    input_path = Path(args.path)
    conn = connect(normalize_db_path(args.db, root), args.journal_mode)
    ensure_schema(conn)
    rows_seen = rows_written = conflicts = duplicates = 0
    with conn:
        repo_id = ensure_repository(conn, root)
        import_id = start_import(conn, repo_id, "lattice_import", {"path": str(input_path)})
        source_id = ensure_source_record(conn, repo_id, "lattice_import", source_path=str(input_path), raw_ref="jsonl")
        for raw in input_path.read_text(encoding="utf-8", errors="replace").splitlines():
            if not raw:
                continue
            rows_seen += 1
            try:
                row = json.loads(raw)
            except json.JSONDecodeError:
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, "jsonl", f"line:{rows_seen}", "", "", "malformed_json")
                continue
            table = row.get("row_type")
            payload = row.get("payload")
            logical_key = str(row.get("logical_key", ""))
            payload_hash = str(row.get("payload_sha256", ""))
            if table == "lattice_unavailable" and isinstance(payload, dict):
                ensure_source_record(
                    conn,
                    repo_id,
                    "recovery",
                    source_path=str(input_path),
                    raw_ref=logical_key,
                    raw_text=raw if not getattr(args, "redact_raw", False) else None,
                    parsed=payload,
                    parse_status="spooled_lattice_unavailable",
                    fact_confidence="observed",
                )
                rows_written += 1
                continue
            if table not in REQUIRED_TABLES or not isinstance(payload, dict):
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, str(table), logical_key, "", payload_hash, "unsupported_row")
                continue
            columns = table_columns(conn, table)
            pk = table_primary_key(conn, table)
            filtered = {k: v for k, v in payload.items() if k in columns}
            if not filtered:
                continue
            existing = None
            if pk and filtered.get(pk) is not None:
                existing = conn.execute(f"select * from {table} where {pk}=?", (filtered[pk],)).fetchone()
            if existing:
                if table in {"schema_meta", "schema_migrations"}:
                    duplicates += 1
                    continue
                existing_payload = {key: existing[key] for key in columns}
                existing_hash = sha256_text(json_dumps(existing_payload))
                if existing_hash == payload_hash or sha256_text(json_dumps(filtered)) == payload_hash:
                    duplicates += 1
                    continue
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, table, logical_key, existing_hash, payload_hash, "kept_existing")
                continue
            colnames = list(filtered.keys())
            placeholders = ",".join("?" for _ in colnames)
            try:
                conn.execute(
                    f"insert into {table}({', '.join(colnames)}) values ({placeholders})",
                    [filtered[key] for key in colnames],
                )
                rows_written += 1
            except sqlite3.IntegrityError as exc:
                conflicts += 1
                record_import_conflict(conn, import_id, repo_id, table, logical_key, "", payload_hash, f"integrity_error:{exc}")
        finish_import(
            conn,
            import_id,
            "conflicts" if conflicts else "ok",
            rows_seen,
            rows_written,
            conflicts,
            {"duplicates": duplicates},
        )
        record_file_event(conn, repo_id, "import_reconciled", source_id=source_id, details={"path": str(input_path), "conflicts": conflicts})
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
) -> None:
    conn.execute(
        """
        insert into lattice_import_conflicts(import_id, repo_id, row_type, logical_key, existing_hash, incoming_hash, resolution, details_json)
        values (?, ?, ?, ?, ?, ?, 'kept_existing', ?)
        """,
        (import_id, repo_id, row_type, logical_key, existing_hash or None, incoming_hash or None, json_dumps({"resolution": resolution})),
    )


def create_backup(conn: sqlite3.Connection, db_path: Path, output: str | None = None) -> Path:
    if output:
        backup_path = Path(output)
    else:
        backup_dir = db_path.parent / "backups"
        backup_dir.mkdir(parents=True, exist_ok=True)
        chmod_private(backup_dir, is_dir=True)
        backup_path = backup_dir / f"lattice-backup-{epoch_now()}.sqlite3"
    backup_path.parent.mkdir(parents=True, exist_ok=True)
    chmod_private(backup_path.parent, is_dir=True)
    backup_conn = sqlite3.connect(str(backup_path))
    try:
        conn.backup(backup_conn)
    finally:
        backup_conn.close()
    chmod_private(backup_path)
    return backup_path


def command_backup(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    db_path = normalize_db_path(args.db, root)
    conn = connect(db_path, args.journal_mode)
    ensure_schema(conn)
    backup_path = create_backup(conn, db_path, output=args.output)
    repo_id = ensure_repository(conn, root)
    with conn:
        source_id = ensure_source_record(conn, repo_id, "artifact", source_path=str(backup_path), raw_ref="backup")
        create_artifact_ref(conn, repo_id, cycle_pk=None, source_id=source_id, artifact_kind="backup", path=str(backup_path))
    conn.close()
    print_json({"status": "ok", "backup_path": str(backup_path)})
    return EXIT_SUCCESS


def record_recovery_artifact_tree(
    conn: sqlite3.Connection,
    repo_id: int,
    source_id: int,
    artifact_kind: str,
    root_path: Path,
    *,
    limit: int = 500,
) -> int:
    if not root_path.exists():
        return 0
    if root_path.is_file():
        files = [root_path]
    else:
        files = [p for p in sorted(root_path.rglob("*")) if p.is_file()]
    count = 0
    for path in files[:limit]:
        create_artifact_ref(
            conn,
            repo_id,
            cycle_pk=None,
            source_id=source_id,
            artifact_kind=artifact_kind,
            path=str(path),
            details={"recovery_scan_root": str(root_path)},
        )
        count += 1
    return count


def recover_artifact_refs(root: Path, db_path: Path, journal_mode: str) -> list[str]:
    conn = connect(db_path, journal_mode)
    ensure_schema(conn)
    recorded: list[str] = []
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(conn, repo_id, "recovery", raw_ref="recover_artifacts")
        artifact_roots = [
            ("startup_anomaly_state", root / "runtime/startup-anomaly-gates"),
            ("transcript", root / "runtime/upkeeper-transcripts"),
            ("postmortem_report", root / "runtime/journals/upkeeper-postmortems"),
        ]
        for env_name in ("CODEX_WRAPPER_HEALTH_STATE_DIR", "CODEX_WRAPPER_HEALTH_ARCHIVE_DIR"):
            configured = os.environ.get(env_name)
            if configured:
                artifact_roots.append(("wrapper_health_state", Path(configured)))
        for artifact_kind, artifact_root in artifact_roots:
            count = record_recovery_artifact_tree(conn, repo_id, source_id, artifact_kind, artifact_root)
            if count:
                recorded.append(f"{artifact_kind}:{artifact_root}:{count}")
        for log_artifact in sorted(root.glob("Upkeeper.log.*")):
            count = record_recovery_artifact_tree(conn, repo_id, source_id, "upkeeper_log", log_artifact, limit=1)
            if count:
                recorded.append(f"upkeeper_log:{log_artifact}:{count}")
        quota_root = root / "runtime/journals/upkeeper-postmortems"
        if quota_root.exists():
            for marker in sorted(quota_root.rglob("primary-quota-blocked-until.txt")):
                count = record_recovery_artifact_tree(conn, repo_id, source_id, "quota_block_marker", marker, limit=1)
                if count:
                    recorded.append(f"quota_block_marker:{marker}:{count}")
    conn.close()
    return recorded


def command_recover(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    db_path = normalize_db_path(args.db, root)
    conn = connect(db_path, args.journal_mode, create_parent=True)
    init_schema(conn, root)
    sources = []
    backup_path = None
    if args.backup_first and db_path.exists():
        backup_path = create_backup(conn, db_path)
        sources.append(f"backup:{backup_path}")
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(conn, repo_id, "recovery", raw_ref="recover", parsed={"root": str(root)})
        if backup_path is not None:
            create_artifact_ref(conn, repo_id, cycle_pk=None, source_id=source_id, artifact_kind="backup", path=str(backup_path))
    conn.close()
    status = "ok"
    if inside_git_repo(root):
        rc = command_import_git(args)
        sources.append(f"git:{rc}")
    log_path = root / "Upkeeper.log"
    if log_path.exists():
        log_args = argparse.Namespace(**vars(args))
        log_args.path = str(log_path)
        log_args.raw = False
        command_import_upkeeper_log(log_args)
        sources.append(str(log_path))
    change_notes = sorted(root.glob("change_notes_*.md"))
    if change_notes:
        notes_args = argparse.Namespace(**vars(args))
        notes_args.paths = [str(p) for p in change_notes]
        notes_args.raw = False
        command_import_change_notes(notes_args)
        sources.extend(str(p) for p in change_notes)
    for export in sorted((db_path.parent / "exports").glob("*.jsonl")):
        import_args = argparse.Namespace(**vars(args))
        import_args.path = str(export)
        import_args.max_conflicts = args.max_conflicts
        command_import_jsonl(import_args)
        sources.append(str(export))
    for recovery_jsonl in sorted((db_path.parent / "recovery").glob("*.jsonl")):
        import_args = argparse.Namespace(**vars(args))
        import_args.path = str(recovery_jsonl)
        import_args.max_conflicts = args.max_conflicts
        command_import_jsonl(import_args)
        sources.append(str(recovery_jsonl))
    for marker_root in [root / "runtime/unaddressed-tool-failures/open", root / "runtime/unaddressed-tool-failures/resolved"]:
        if marker_root.exists():
            import_failure_markers(root, db_path, args.journal_mode, marker_root)
            sources.append(str(marker_root))
    sources.extend(recover_artifact_refs(root, db_path, args.journal_mode))
    if not sources:
        status = "incomplete"
    recovery_dir = db_path.parent / "recovery"
    recovery_dir.mkdir(parents=True, exist_ok=True)
    chmod_private(recovery_dir, is_dir=True)
    report_path = recovery_dir / f"recovery-{epoch_now()}.json"
    report = {"status": status, "sources": sources}
    report_path.write_text(json_dumps(report) + "\n", encoding="utf-8")
    chmod_private(report_path)
    print_json({"status": status, "sources": sources, "recovery_report": str(report_path)})
    return EXIT_SUCCESS if status == "ok" else EXIT_RECOVERY_INCOMPLETE


def import_failure_markers(root: Path, db_path: Path, journal_mode: str, marker_root: Path) -> None:
    conn = connect(db_path, journal_mode)
    ensure_schema(conn)
    with conn:
        repo_id = ensure_repository(conn, root)
        for path in marker_root.glob("*.json"):
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            target = normalize_rel_path(str(data.get("target_path", "")))
            file_id = ensure_file(conn, repo_id, target) if target else None
            source_id = ensure_source_record(conn, repo_id, "tool_failure_marker", source_path=str(path), raw_ref=str(data.get("marker_id", path.stem)), parsed=data)
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
                    str(data.get("marker_id", path.stem)),
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
    row = conn.execute("select file_id from files where repo_id=? and current_path=?", (repo_id, path)).fetchone()
    if not row:
        return []
    file_id = int(row["file_id"])
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
        file_row = conn.execute("select file_id from files where repo_id=? and current_path=?", (repo_id, path)).fetchone()
        completed = 0
        if file_row:
            completed = int(
                conn.execute(
                    """
                    select count(*) from file_pass_runs
                    where repo_id=? and file_id=? and pass_code=? and outcome in ('clean','fixed','regression_found')
                    """,
                    (repo_id, int(file_row["file_id"]), pass_code),
                ).fetchone()[0]
            )
        if completed == 0:
            rows.append({"path": path, "pass_code": pass_code, "completed_count": 0, "scope": args.scope})
    return rows


def query_pass_counts(conn: sqlite3.Connection, root: Path, repo_id: int, args: argparse.Namespace) -> list[dict[str, Any]]:
    return pass_counts_for_path(conn, repo_id, normalize_rel_path(args.path), args.pass_code)


def query_file_history(conn: sqlite3.Connection, root: Path, repo_id: int, args: argparse.Namespace) -> list[dict[str, Any]]:
    path = normalize_rel_path(args.path)
    file_row = conn.execute("select file_id from files where repo_id=? and current_path=?", (repo_id, path)).fetchone()
    if not file_row:
        return []
    file_id = int(file_row["file_id"])
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
    for row in conn.execute(
        """
        select g.change_epoch as epoch, 'git_change' as kind, g.path, g.status, c.sha, c.subject
        from git_file_changes g join git_commits c on c.commit_id=g.commit_id
        where g.repo_id=? and g.file_id=?
        order by g.change_epoch, g.git_file_change_id
        """,
        (repo_id, file_id),
    ):
        rows.append(dict(row))
    return sorted(rows, key=lambda item: (item.get("epoch") or 0, str(item.get("kind"))))


def query_regressions(conn: sqlite3.Connection, root: Path, repo_id: int, args: argparse.Namespace) -> list[dict[str, Any]]:
    params: list[Any] = [repo_id]
    where = "where r.repo_id=?"
    if args.path:
        row = conn.execute("select file_id from files where repo_id=? and current_path=?", (repo_id, normalize_rel_path(args.path))).fetchone()
        if not row:
            return []
        where += " and r.file_id=?"
        params.append(int(row["file_id"]))
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
        file_row = conn.execute("select file_id from files where repo_id=? and current_path=?", (repo_id, path)).fetchone()
        file_id = int(file_row["file_id"]) if file_row else None
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
        file_row = conn.execute("select file_id from files where repo_id=? and current_path=?", (repo_id, path)).fetchone()
        if not file_row:
            continue
        file_id = int(file_row["file_id"])
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
        file_row = conn.execute("select file_id from files where repo_id=? and current_path=?", (repo_id, path)).fetchone()
        file_id = int(file_row["file_id"]) if file_row else None
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


def query_selection_candidates(conn: sqlite3.Connection, root: Path, repo_id: int, args: argparse.Namespace) -> list[dict[str, Any]]:
    rows = live_candidate_paths(root)
    eligible = [row for row in rows if row["candidate_state"] == "eligible"]
    excluded = [row for row in rows if row["candidate_state"] != "eligible"]
    mode = args.mode
    if mode.startswith("never-pass:"):
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
        params.append(normalize_rel_path(args.path))
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
    conn = connect(normalize_db_path(args.db, root), args.journal_mode)
    ensure_schema(conn)
    with conn:
        repo_id = ensure_repository(conn, root)
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
    conn = connect(normalize_db_path(args.db, root), args.journal_mode)
    ensure_schema(conn)
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(conn, repo_id, args.source_kind, raw_ref="mark-regression", parsed=vars(args))
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
    conn = connect(normalize_db_path(args.db, root), args.journal_mode)
    ensure_schema(conn)
    cutoff = epoch_now() - int(args.older_than_days or 0) * 86400 if args.older_than_days else None
    actions: list[dict[str, Any]] = []
    with conn:
        repo_id = ensure_repository(conn, root)
        source_id = ensure_source_record(conn, repo_id, "operator", raw_ref="prune", parsed=vars(args))
        if args.raw_only:
            sql = "update source_records set raw_text=null where raw_text is not null"
            params: tuple[Any, ...] = ()
            if cutoff:
                sql += " and imported_epoch<?"
                params = (cutoff,)
            count = conn.execute("select count(*) from source_records where raw_text is not null" + (" and imported_epoch<?" if cutoff else ""), params).fetchone()[0]
            actions.append({"action": "raw_text_null", "rows": count})
            if not args.dry_run:
                conn.execute(sql, params)
        if args.candidate_details:
            sql = """
                delete from selection_candidates
                where candidate_state != 'selected'
                  and selection_run_id in (select selection_run_id from selection_runs where generated_epoch<?)
            """
            count = 0
            if cutoff:
                count = conn.execute(
                    """
                    select count(*) from selection_candidates
                    where candidate_state != 'selected'
                      and selection_run_id in (select selection_run_id from selection_runs where generated_epoch<?)
                    """,
                    (cutoff,),
                ).fetchone()[0]
                actions.append({"action": "candidate_details_delete", "rows": count})
                if not args.dry_run:
                    conn.execute(sql, (cutoff,))
        if args.transient_artifacts:
            rows = [
                dict(row)
                for row in conn.execute(
                    """
                    select artifact_id, path from artifact_refs
                    where retained=1 and artifact_kind in ('transcript','compiled_prompt','last_message')
                    """
                )
            ]
            actions.append({"action": "transient_artifacts_unretain", "rows": len(rows)})
            if not args.dry_run:
                conn.execute(
                    """
                    update artifact_refs set retained=0
                    where retained=1 and artifact_kind in ('transcript','compiled_prompt','last_message')
                    """
                )
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
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("init")
    p.set_defaults(func=command_init)

    p = sub.add_parser("doctor")
    p.add_argument("--backup", action="store_true")
    p.add_argument("--backup-output")
    p.set_defaults(func=command_doctor)

    p = sub.add_parser("record-cycle-start")
    add_cycle_args(p)
    p.add_argument("--execution-origin", default="")
    p.add_argument("--model", default="")
    p.add_argument("--effort", default="")
    p.add_argument("--mode", default="")
    p.add_argument("--config-file", default="")
    p.add_argument("--branch-name", default="")
    p.add_argument("--head-sha", default="")
    p.add_argument("--head-tree-sha", default="")
    p.add_argument("--upstream-ref", default="")
    p.add_argument("--dirty-path-count", default="0")
    p.add_argument("--dry-run", default="0")
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
    p.add_argument("--status-marker", default="")
    p.add_argument("--review-outcome", default="")
    p.add_argument("--review-selected-path", default="")
    p.add_argument("--codex-exit", type=int)
    p.add_argument("--wrapper-exit", type=int)
    p.add_argument("--finish-reason", default="")
    p.add_argument("--finish-level", default="")
    p.add_argument("--codex-exec-started", type=int, default=0)
    p.add_argument("--dry-run", default="0")
    p.add_argument("--selected-path", default="")
    p.add_argument("--last-message-file", default="")
    p.add_argument("--transcript-path", default="")
    p.add_argument("--compiled-prompt-path", default="")
    p.add_argument("--log-path", default="")
    p.add_argument("--snapshot-kind", default="after_codex")
    p.add_argument("--end-epoch", type=int)
    p.set_defaults(func=command_record_cycle_finish)

    p = sub.add_parser("record-worktree-snapshot")
    add_cycle_args(p, required=False)
    p.add_argument("--snapshot-kind", required=True)
    p.set_defaults(func=command_record_worktree_snapshot)

    p = sub.add_parser("record-pass-result")
    add_cycle_args(p, required=False)
    p.add_argument("--pass", dest="pass_code")
    p.add_argument("--file", dest="path")
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
    p.add_argument("--redact-raw", action="store_true")
    p.add_argument("--redact-paths", action="store_true")
    p.add_argument("--redact-contributors", action="store_true")
    p.set_defaults(func=command_export_jsonl)

    p = sub.add_parser("import-jsonl")
    p.add_argument("path")
    p.add_argument("--max-conflicts", type=int, default=0)
    p.set_defaults(func=command_import_jsonl)

    p = sub.add_parser("backup")
    p.add_argument("--output")
    p.set_defaults(func=command_backup)

    p = sub.add_parser("recover")
    p.add_argument("--backup-first", action="store_true", default=True)
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
    try:
        return int(args.func(args))
    except sqlite3.IntegrityError as exc:
        print(f"upkeeper_lattice: integrity failure: {exc}", file=sys.stderr)
        return EXIT_INTEGRITY
    except sqlite3.Error as exc:
        print(f"upkeeper_lattice: database error: {exc}", file=sys.stderr)
        return EXIT_DB_UNAVAILABLE
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
