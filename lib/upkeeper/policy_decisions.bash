UPKEEPER_POLICY_DECISION_SCHEMA_VERSION="1"

upkeeper_policy_decision_schema_version() {
  printf '%s\n' "$UPKEEPER_POLICY_DECISION_SCHEMA_VERSION"
}

upkeeper_policy_decision_profile_is_known() {
  case "$1" in
    operator|wrapper-local-control-plane|backend-codex-default-review|backend-codex-bug-report-only|backend-codex-issue-comment|backend-codex-issue-review|backend-codex-issue-apply|fallback-postmortem-backend|lattice-cli|local-validation-ci)
      return 0
      ;;
  esac
  return 1
}

upkeeper_policy_decision_bool_is_json() {
  case "$1" in
    true|false)
      return 0
      ;;
  esac
  return 1
}

upkeeper_policy_decision_csv_json_array() {
  local csv="$1"

  jq -Rcn --arg csv "$csv" '
    $csv
    | split(",")
    | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
    | map(select(length > 0))
  '
}

upkeeper_policy_decision_validate_json() {
  local decision_json="$1"

  jq -e '
    def nonempty_string:
      type == "string" and length > 0;
    def string_array:
      type == "array" and all(.[]; type == "string" and length > 0);
    def action_array:
      type == "array" and all(.[]; type == "string" and test("^[a-z][a-z0-9_.:-]*$"));
    def known_profile($profile):
      [
        "operator",
        "wrapper-local-control-plane",
        "backend-codex-default-review",
        "backend-codex-bug-report-only",
        "backend-codex-issue-comment",
        "backend-codex-issue-review",
        "backend-codex-issue-apply",
        "fallback-postmortem-backend",
        "lattice-cli",
        "local-validation-ci"
      ] | index($profile) != null;

    type == "object"
    and .schema_version == 1
    and (.decision_id | nonempty_string and test("^[A-Za-z0-9][A-Za-z0-9_.:-]*$"))
    and (.capability_profile | nonempty_string and known_profile(.))
    and (.mode | nonempty_string)
    and (.selected_target | nonempty_string)
    and ([.may_contact_backend, .may_write_source, .may_retarget, .may_restore_backup, .may_use_network, .may_file_issue] | all(.[]; type == "boolean"))
    and (.allowed_writes | string_array)
    and (.denied_actions | action_array)
    and (.reasons | string_array and length > 0)
    and ((.evidence // []) | string_array)
  ' >/dev/null <<<"$decision_json"
}

upkeeper_policy_decision_emit() {
  if [[ $# -lt 13 || $# -gt 14 ]]; then
    printf 'Upkeeper: policy decision emit expected 13 or 14 arguments, got %d\n' "$#" >&2
    return 2
  fi

  local decision_id="$1"
  local capability_profile="$2"
  local mode="$3"
  local selected_target="$4"
  local may_contact_backend="$5"
  local may_write_source="$6"
  local may_retarget="$7"
  local may_restore_backup="$8"
  local may_use_network="$9"
  local may_file_issue="${10}"
  local allowed_writes_csv="${11}"
  local denied_actions_csv="${12}"
  local reasons_csv="${13}"
  local evidence_csv="${14:-}"
  local allowed_writes_json denied_actions_json reasons_json evidence_json decision_json
  local bool_value

  if ! upkeeper_policy_decision_profile_is_known "$capability_profile"; then
    printf 'Upkeeper: unknown policy decision capability profile: %s\n' "$capability_profile" >&2
    return 2
  fi

  for bool_value in \
    "$may_contact_backend" \
    "$may_write_source" \
    "$may_retarget" \
    "$may_restore_backup" \
    "$may_use_network" \
    "$may_file_issue"
  do
    if ! upkeeper_policy_decision_bool_is_json "$bool_value"; then
      printf 'Upkeeper: policy decision boolean must be true or false, got: %s\n' "$bool_value" >&2
      return 2
    fi
  done

  allowed_writes_json="$(upkeeper_policy_decision_csv_json_array "$allowed_writes_csv")" || return 1
  denied_actions_json="$(upkeeper_policy_decision_csv_json_array "$denied_actions_csv")" || return 1
  reasons_json="$(upkeeper_policy_decision_csv_json_array "$reasons_csv")" || return 1
  evidence_json="$(upkeeper_policy_decision_csv_json_array "$evidence_csv")" || return 1

  decision_json="$(
    jq -cn \
      --argjson schema_version "$UPKEEPER_POLICY_DECISION_SCHEMA_VERSION" \
      --arg decision_id "$decision_id" \
      --arg capability_profile "$capability_profile" \
      --arg mode "$mode" \
      --arg selected_target "$selected_target" \
      --argjson may_contact_backend "$may_contact_backend" \
      --argjson may_write_source "$may_write_source" \
      --argjson may_retarget "$may_retarget" \
      --argjson may_restore_backup "$may_restore_backup" \
      --argjson may_use_network "$may_use_network" \
      --argjson may_file_issue "$may_file_issue" \
      --argjson allowed_writes "$allowed_writes_json" \
      --argjson denied_actions "$denied_actions_json" \
      --argjson reasons "$reasons_json" \
      --argjson evidence "$evidence_json" \
      '{
        schema_version: $schema_version,
        decision_id: $decision_id,
        capability_profile: $capability_profile,
        mode: $mode,
        selected_target: $selected_target,
        may_contact_backend: $may_contact_backend,
        may_write_source: $may_write_source,
        may_retarget: $may_retarget,
        may_restore_backup: $may_restore_backup,
        may_use_network: $may_use_network,
        may_file_issue: $may_file_issue,
        allowed_writes: $allowed_writes,
        denied_actions: $denied_actions,
        reasons: $reasons,
        evidence: $evidence
      }'
  )" || return 1

  upkeeper_policy_decision_validate_json "$decision_json" || {
    printf 'Upkeeper: generated policy decision failed schema validation\n' >&2
    return 1
  }

  printf '%s\n' "$decision_json"
}
