# Shared change-scope classifiers for the docs-only and low-risk fast paths.

upkeeper_change_scope_path_is_docs_only() {
  local path="${1:-}"

  case "$path" in
    README.md|AGENTS.md|PLANS.md|change_notes_[0-9][0-9][0-9][0-9].md)
      return 0
      ;;
    docs/*.md|docs/*/*.md|prompts/*.md|templates/*.md)
      return 0
      ;;
    .github/pull_request_template.md|.github/ISSUE_TEMPLATE/*.yml)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

upkeeper_change_scope_path_is_low_risk() {
  local path="${1:-}"

  if upkeeper_change_scope_path_is_docs_only "$path"; then
    return 0
  fi

  case "$path" in
    Upkeeper.conf|configurations/*.conf)
      return 0
      ;;
    completions/*.bash|tests/*.bash|testruns/*.sh)
      return 0
      ;;
    tools/*.sh)
      case "$path" in
        tools/docs_only_fast_path.sh|tools/validate_upkeeper.sh|tools/run_validation_phases.sh|tools/check_public_docs.sh|tools/setup_ci_dependencies.sh)
          return 1
          ;;
        *)
          return 0
          ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}
