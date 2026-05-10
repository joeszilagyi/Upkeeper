# Bash completion for the central Upkeeper launcher family.
#
# Usage:
#   source completions/upkeeper.bash

if [[ -z "${BASH_VERSION:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi

_upkeeper_complete_csv_value() {
  local cur="$1"
  local opt="${cur%%=*}="
  local prefix="${cur#*=}"
  local values="$2"

  COMPREPLY=()
  mapfile -t COMPREPLY < <(compgen -W "$values" -- "$prefix")
  for i in "${!COMPREPLY[@]}"; do
    COMPREPLY[$i]="$opt${COMPREPLY[$i]}"
  done
}

_upkeeper_complete_path_value() {
  local cur="$1"
  local opt="${cur%%=*}="
  local prefix="${cur#*=}"

  COMPREPLY=()
  mapfile -t COMPREPLY < <(compgen -f -- "$prefix")
  for i in "${!COMPREPLY[@]}"; do
    COMPREPLY[$i]="$opt${COMPREPLY[$i]}"
  done
}

_upkeeper_complete() {
  local cur prev opts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev=""
  if (( COMP_CWORD > 0 )); then
    prev="${COMP_WORDS[COMP_CWORD-1]}"
  fi

  opts="
    --help --version --config-file= --no-config
    --prompt-file --prompt
    --review-module= --review-modules= --p24 --p25 --p26 --p27 --p28 --p29
    --model-override=
    --target-file= --target-root= --target-dir= --target-depth= --target-max-depth=
    --selection-source= --selection-order= --random-target
    --refresh-manifest --manifest-file=
    --include-glob= --include-globs= --exclude-glob= --exclude-globs=
    --selection-review-modules=
    --ignore-failure-queue --bypass-failure-queue --backup-queue -backup_queue
    --prompt-pass= --max-cover
    --bug-report-only --file-bug-only --report-bug-only
    --fix-next-issue --fix-oldest-bug --fix-issue= --issue-workflow-stage=
  "

  case "$prev" in
    --prompt-file)
      mapfile -t COMPREPLY < <(compgen -f -- "$cur")
      return 0
      ;;
    --prompt)
      return 0
      ;;
  esac

  case "$cur" in
    --config-file=*|--target-file=*|--target-root=*|--target-dir=*|--manifest-file=*)
      _upkeeper_complete_path_value "$cur"
      return 0
      ;;
    --review-module=*)
      _upkeeper_complete_csv_value "$cur" "p24 p25 p26 p27 p28 p29 de-llm contract docs educational-debrief unit-test-harvesting reuse library-reuse function-reuse asset-reuse"
      return 0
      ;;
    --review-modules=*|--selection-review-modules=*)
      _upkeeper_complete_csv_value "$cur" "p24 p25 p26 p27 p28 p29 p24,p25,p26,p27,p28,p29"
      return 0
      ;;
    --model-override=*)
      _upkeeper_complete_csv_value "$cur" "5.5_xhigh 5.3-codex-spark_xhigh spark_xhigh"
      return 0
      ;;
    --selection-source=*)
      _upkeeper_complete_csv_value "$cur" "manifest enumerate"
      return 0
      ;;
    --selection-order=*)
      _upkeeper_complete_csv_value "$cur" "oldest newest random"
      return 0
      ;;
    --prompt-pass=*)
      _upkeeper_complete_csv_value "$cur" "all"
      return 0
      ;;
    --target-depth=*|--target-max-depth=*)
      _upkeeper_complete_csv_value "$cur" "0 1 2 3 4 5 10"
      return 0
      ;;
    --fix-issue=*)
      return 0
      ;;
    --issue-workflow-stage=*)
      _upkeeper_complete_csv_value "$cur" "comment review apply"
      return 0
      ;;
    --*)
      mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur")
      return 0
      ;;
    -*)
      mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur")
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

_flameon_complete() {
  local cur prev opts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev=""
  if (( COMP_CWORD > 0 )); then
    prev="${COMP_WORDS[COMP_CWORD-1]}"
  fi
  opts="--help -h --silent --basic --debug1 --model-override= --model --reasoning-effort -backup_queue --backup-queue"
  case "$prev" in
    --model)
      mapfile -t COMPREPLY < <(compgen -W "gpt-5.5 gpt-5.3-codex-spark" -- "$cur")
      return 0
      ;;
    --reasoning-effort)
      mapfile -t COMPREPLY < <(compgen -W "xhigh" -- "$cur")
      return 0
      ;;
  esac
  case "$cur" in
    --model-override=*)
      _upkeeper_complete_csv_value "$cur" "5.5_xhigh 5.3-codex-spark_xhigh spark_xhigh"
      return 0
      ;;
  esac
  mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur")
}

_chimneysweep_complete() {
  local cur prev opts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev=""
  if (( COMP_CWORD > 0 )); then
    prev="${COMP_WORDS[COMP_CWORD-1]}"
  fi
  opts="--help -h --silent --basic --debug1 --model-override= --model --reasoning-effort --workflow= --dry-run --json"
  case "$prev" in
    --model)
      mapfile -t COMPREPLY < <(compgen -W "gpt-5.5 gpt-5.3-codex-spark" -- "$cur")
      return 0
      ;;
    --reasoning-effort)
      mapfile -t COMPREPLY < <(compgen -W "xhigh" -- "$cur")
      return 0
      ;;
  esac
  case "$cur" in
    --model-override=*)
      _upkeeper_complete_csv_value "$cur" "5.5_xhigh 5.3-codex-spark_xhigh spark_xhigh"
      return 0
      ;;
    --workflow=*)
      _upkeeper_complete_csv_value "$cur" "comment-review-apply comment-review comment review apply staged"
      return 0
      ;;
  esac
  mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur")
}

complete -F _upkeeper_complete Upkeeper ./Upkeeper Upkeeper.sh ./Upkeeper.sh
complete -F _flameon_complete FlameOn ./FlameOn
complete -F _chimneysweep_complete ChimneySweep ./ChimneySweep
