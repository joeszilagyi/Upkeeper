#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'noop_path_probe_test: FAIL: %s\n' "$*" >&2
  exit 1
}

output="$("$PROJECT_ROOT/tools/measure_upkeeper_noop_path.sh" --budget-ms 30000)"
[[ "$output" == *"outcome=pass"* ]] || fail "private probe did not pass its normal budget: $output"
[[ "$output" == *"backend_exec_started=0"* ]] || fail "private probe did not prove no backend launch: $output"
[[ "$output" == *"fixture_state=private"* ]] || fail "private probe did not identify fixture containment: $output"
[[ "$output" =~ python_subprocesses=[0-9]+ ]] || fail "private probe omitted Python subprocess count: $output"
[[ "$output" =~ lattice_python_subprocesses=[0-9]+ ]] || fail "private probe omitted Lattice subprocess count: $output"
[[ "$output" =~ control_plane_audit_python_subprocesses=[0-9]+ ]] || fail "private probe omitted audit subprocess count: $output"

set +e
over_budget_output="$("$PROJECT_ROOT/tools/measure_upkeeper_noop_path.sh" --budget-ms 1 2>&1)"
over_budget_rc=$?
set -e
[[ "$over_budget_rc" -eq 2 ]] || fail "probe did not fail its enforced one-millisecond regression budget: rc=$over_budget_rc output=$over_budget_output"
[[ "$over_budget_output" == *"outcome=budget_exceeded"* ]] || fail "budget failure did not retain its measured outcome: $over_budget_output"
[[ "$over_budget_output" == *"backend_exec_started=0"* ]] || fail "budget failure did not retain the no-backend invariant: $over_budget_output"

printf 'noop_path_probe_test: ok\n'
