# Shared change-scope classifiers for CI validation gates.  A path is eligible
# for the reduced gate only when it is in this deliberately small editorial
# allowlist; unknown paths fail closed into full validation.

upkeeper_change_scope_path_is_docs_only() {
  local path="${1:-}"

  case "$path" in
    README.md|change_notes_[0-9][0-9][0-9][0-9].md|\
    docs/known-issues.md|docs/prd.md|docs/roadmap.md)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

upkeeper_change_scope_path_is_low_risk() {
  local path="${1:-}"

  upkeeper_change_scope_path_is_docs_only "$path"
}
