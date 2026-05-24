# Review-module registry.
#
# This module is the narrow source of truth for reusable review-module ids,
# aliases, prompt paths, titles, and help summaries. Keep behavior callers in
# codex I/O, prompt compilation, help text, and validation consuming these rows
# instead of adding another scattered case block.

review_module_registry_rows() {
  cat <<'EOF'
p24|prompts/p24-de-llm-ing-viability-review.md|P24 - De-LLM-ing Viability Review|de-llm,de-llm-ing,dellm,de-llming|P24 de-LLM-ing viability review
p25|prompts/p25-contract-intent-compliance-review.md|P25 - Contract And Intent Compliance Review|contract,contract-intent,intent,design-intent,architecture,architecture-fitness|P25 contract and intent compliance review
p26|prompts/p26-public-documentation-review.md|P26 - Public Documentation And Readability Review|docs,documentation,public-docs,public-documentation,doc-rigor,readability|P26 public documentation review
p27|prompts/p27-educational-debrief-review.md|P27 - After-Action Review|after-action,after-action-review,aar,education,educational,educational-mode,teaching,teach,debrief,learning|P27 after-action review
p28|prompts/p28-unit-test-harvesting-review.md|P28 - Unit Test Harvesting Review|unit-test,unit-tests,unit-testing,test-harvest,test-harvesting,fixture-harvest,fixture-harvesting|P28 unit test harvesting review
p29|prompts/p29-reuse-harvesting-review.md|# P29 Reuse Harvesting Review|reuse,reuse-harvest,reuse-harvesting,reusable,library-reuse,function-reuse,asset-reuse,consolidation,extract-helper,helper-extraction|P29 reuse harvesting review
p30|prompts/p30-stark-protocol-review.md|# P30 Stark Protocol Review|stark,stark-protocol,permanent-hardening,hardening,non-regression,regression-proof,no-repeat,final-hardening|P30 Stark Protocol permanent hardening review
EOF
}

review_module_ids_csv() {
  review_module_registry_rows | awk -F'|' 'BEGIN { ORS = "," } { print $1 }' | sed 's/,$//'
}

review_module_ids_pipe() {
  review_module_ids_csv | tr ',' '|'
}

review_module_supported_message() {
  review_module_ids_csv | sed 's/,/, /g'
}

review_module_shorthand_usage() {
  local id first=1

  while IFS='|' read -r id _; do
    if [[ "$first" -eq 0 ]]; then
      printf ' '
    fi
    printf '[--%s]' "$id"
    first=0
  done < <(review_module_registry_rows)
}

review_module_shorthand_sentence() {
  local id first=1

  while IFS='|' read -r id _; do
    if [[ "$first" -eq 0 ]]; then
      printf ', '
    fi
    printf -- '--%s' "$id"
    first=0
  done < <(review_module_registry_rows)
}

review_module_repeated_option_examples() {
  local option_prefix="$1"
  local id count=0 index=0
  local -a examples=()

  while IFS='|' read -r id _; do
    examples+=("${option_prefix}${id}")
  done < <(review_module_registry_rows)

  count="${#examples[@]}"
  for index in "${!examples[@]}"; do
    if [[ "$index" -gt 0 ]]; then
      if [[ "$index" -eq $((count - 1)) ]]; then
        printf ', or '
      else
        printf ', '
      fi
    fi
    printf '%s' "${examples[$index]}"
  done
}

normalize_review_module() {
  local raw_module="$1"
  local module id prompt_path title aliases help_summary alias
  local -a alias_list=()

  module="$(printf '%s' "$raw_module" | tr '[:upper:]_' '[:lower:]-')"
  while IFS='|' read -r id prompt_path title aliases help_summary; do
    if [[ "$module" == "$id" ]]; then
      printf '%s' "$id"
      return 0
    fi
    IFS=',' read -r -a alias_list <<<"$aliases"
    for alias in "${alias_list[@]}"; do
      if [[ "$module" == "$alias" ]]; then
        printf '%s' "$id"
        return 0
      fi
    done
  done < <(review_module_registry_rows)

  return 1
}

review_module_prompt_relative_path() {
  local raw_module="$1"
  local module id prompt_path title aliases help_summary

  module="$(normalize_review_module "$raw_module")" || return 1
  while IFS='|' read -r id prompt_path title aliases help_summary; do
    if [[ "$module" == "$id" ]]; then
      printf '%s' "$prompt_path"
      return 0
    fi
  done < <(review_module_registry_rows)

  return 1
}

review_module_prompt_path() {
  local prompt_path

  prompt_path="$(review_module_prompt_relative_path "$1")" || return 1
  printf '%s/%s' "$UPKEEPER_IMPLEMENTATION_DIR" "$prompt_path"
}

review_module_flag_help_lines() {
  local id prompt_path title aliases help_summary

  while IFS='|' read -r id prompt_path title aliases help_summary; do
    printf '  - --review-module=%s appends the central %s module for this invoked cycle.\n' "$id" "$help_summary"
  done < <(review_module_registry_rows)
}
