# Quota snapshot reader and projector.
#
# Codex writes rate-limit state into session JSONL files, not a stable wrapper
# API. The Python block keeps parsing isolated and returns one compact JSON
# object to Bash. Guardrails only trust exact-model buckets whose reset windows
# are still current; stale buckets are evidence, not a stop signal.
quota_metadata_debug_enabled() {
  if declare -F upkeeper_verbose_metadata_enabled >/dev/null 2>&1; then
    upkeeper_verbose_metadata_enabled
  else
    return 1
  fi
}

quota_metadata_path_hmac() {
  local value="${1:-unknown}"

  if declare -F upkeeper_path_hmac >/dev/null 2>&1; then
    upkeeper_path_hmac "$value"
  else
    printf '%s' "$value"
  fi
}

quota_metadata_value_hmac() {
  local namespace="$1"
  local value="${2:-unknown}"

  if declare -F upkeeper_value_hmac >/dev/null 2>&1; then
    upkeeper_value_hmac "quota_$namespace" "$value"
  else
    printf '%s' "$value"
  fi
}

quota_sensitive_log_field() {
  local key="$1"
  local value="${2:-unknown}"

  if quota_metadata_debug_enabled; then
    printf ' %s=%s' "$key" "$(shell_quote "$value")"
  fi
}

quota_sensitive_log_fragment() {
  local fragment="${1:-}"

  if quota_metadata_debug_enabled && [[ -n "$fragment" ]]; then
    printf ' %s' "$fragment"
  fi
}

quota_hashed_log_field() {
  local key="$1"
  local value="${2:-unknown}"
  local namespace="${3:-$1}"

  printf ' %s_hmac=%s' "$key" "$(quota_metadata_value_hmac "$namespace" "$value")"
}

quota_hashed_path_log_field() {
  local key="$1"
  local value="${2:-unknown}"

  printf ' %s_hmac=%s' "$key" "$(quota_metadata_path_hmac "$value")"
}

quota_public_stop_reason() {
  local value="${1:-quota_guardrail_stop}"

  if quota_metadata_debug_enabled; then
    printf '%s' "$value"
  else
    printf 'quota_guardrail_stop'
  fi
}

quota_state_json() {
  local target_model="${1:-$CODEX_MODEL}"
  python3 - "$CODEX_HOME_DIR" "$CODEX_SESSION_SCAN_LIMIT" "$LOG_FILE" "$target_model" <<'PY'
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

codex_home = Path(sys.argv[1]).expanduser()
scan_limit = int(sys.argv[2])
log_path = Path(sys.argv[3])
target_model = sys.argv[4].strip()

cycle_re = re.compile(r"cycle=([A-Za-z0-9T+-]+-\d+)")
start_model_re = re.compile(r"cycle\.start .* model=([A-Za-z0-9._:-]+)")
summary_model_re = re.compile(r"cycle\.summary .* model=([A-Za-z0-9._:-]+)")
summary_re = re.compile(
    r"cycle\.summary .*observed_primary_delta=([0-9]+(?:\.[0-9]+)?) observed_secondary_delta=([0-9]+(?:\.[0-9]+)?) .*status_marker=([^ ]+) .*codex_exit=([0-9]+)"
)

TAIL_SCAN_BYTES = 512 * 1024
HEAD_SCAN_BYTES = 128 * 1024


def snapshot_from_token_count(item, path: Path, source_mtime: float, model_hint):
    payload = item.get("payload") or {}
    rate_limits = payload.get("rate_limits") or {}
    primary = rate_limits.get("primary") or {}
    secondary = rate_limits.get("secondary") or {}
    if not primary or not secondary:
        return None
    return {
        "event_timestamp": item.get("timestamp"),
        "limit_id": rate_limits.get("limit_id"),
        "limit_name": rate_limits.get("limit_name"),
        "plan_type": rate_limits.get("plan_type"),
        "rate_limit_reached_type": rate_limits.get("rate_limit_reached_type"),
        "primary_used_percent": float(primary.get("used_percent") or 0.0),
        "primary_window_minutes": int(primary.get("window_minutes") or 0),
        "primary_resets_at": int(primary.get("resets_at") or 0),
        "secondary_used_percent": float(secondary.get("used_percent") or 0.0),
        "secondary_window_minutes": int(secondary.get("window_minutes") or 0),
        "secondary_resets_at": int(secondary.get("resets_at") or 0),
        "source_path": str(path),
        "source_mtime": source_mtime,
        "model_hint": model_hint,
    }


def model_hint_from_head(path: Path):
    try:
        with path.open("rb") as handle:
            data = handle.read(HEAD_SCAN_BYTES)
    except OSError:
        return None

    text = data.decode("utf-8", errors="ignore")
    for raw_line in text.splitlines():
        try:
            item = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if item.get("type") != "turn_context":
            continue
        payload = item.get("payload") or {}
        context_model = payload.get("model")
        if isinstance(context_model, str) and context_model.strip():
            return context_model.strip()
    return None


def last_token_snapshot_from_tail(path: Path, source_mtime: float, model_hint):
    try:
        with path.open("rb") as handle:
            handle.seek(0, 2)
            size = handle.tell()
            handle.seek(max(0, size - TAIL_SCAN_BYTES))
            data = handle.read()
    except OSError:
        return None

    text = data.decode("utf-8", errors="ignore")
    lines = text.splitlines()
    if data and not data.startswith((b"{", b"\n", b"\r")) and lines:
        lines = lines[1:]
    for raw_line in reversed(lines):
        if '"token_count"' not in raw_line:
            continue
        try:
            item = json.loads(raw_line)
        except json.JSONDecodeError:
            continue
        if item.get("type") != "event_msg":
            continue
        payload = item.get("payload") or {}
        if payload.get("type") != "token_count":
            continue
        snapshot = snapshot_from_token_count(item, path, source_mtime, model_hint)
        if snapshot:
            return snapshot
    return None


def full_session_snapshot(path: Path, source_mtime: float):
    last_snapshot = None
    model_hint = None
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as handle:
            for raw_line in handle:
                try:
                    item = json.loads(raw_line)
                except json.JSONDecodeError:
                    continue
                if item.get("type") == "turn_context":
                    payload = item.get("payload") or {}
                    context_model = payload.get("model")
                    if isinstance(context_model, str) and context_model.strip():
                        model_hint = context_model.strip()
                    continue
                if item.get("type") != "event_msg":
                    continue
                payload = item.get("payload") or {}
                if payload.get("type") != "token_count":
                    continue
                snapshot = snapshot_from_token_count(item, path, source_mtime, model_hint)
                if snapshot:
                    last_snapshot = snapshot
    except OSError:
        return None
    return last_snapshot


def session_snapshot(path: Path):
    try:
        source_mtime = path.stat().st_mtime
    except OSError:
        return None

    model_hint = model_hint_from_head(path)
    snapshot = last_token_snapshot_from_tail(path, source_mtime, model_hint)
    if snapshot and snapshot.get("model_hint"):
        return snapshot
    return full_session_snapshot(path, source_mtime)


def parse_session_snapshots(root: Path, limit: int):
    sessions_root = root / "sessions"
    if not sessions_root.exists():
        return []

    candidates = sorted(
        sessions_root.rglob("*.jsonl"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )[:limit]

    snapshots = []
    for path in candidates:
        snapshot = session_snapshot(path)
        if snapshot:
            snapshots.append(snapshot)

    snapshots.sort(key=lambda item: ((item.get("event_timestamp") or ""), item.get("source_mtime") or 0.0))
    return snapshots


def snapshots_for_target_model(items, model):
    if not model:
        return items, "overall_latest"
    exact = [item for item in items if item.get("model_hint") == model]
    if exact:
        return exact, "exact_model"
    return items, "overall_fallback"


def parse_event_epoch(value):
    if not isinstance(value, str) or not value.strip():
        return None
    normalized = value.strip()
    if normalized.endswith("Z"):
        normalized = f"{normalized[:-1]}+00:00"
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp())


def annotate_snapshot_freshness(snapshot, now):
    event_epoch = parse_event_epoch(snapshot.get("event_timestamp"))
    primary_reset = int(snapshot.get("primary_resets_at") or 0)
    secondary_reset = int(snapshot.get("secondary_resets_at") or 0)
    primary_reset_expired = primary_reset > 0 and primary_reset <= now
    secondary_reset_expired = secondary_reset > 0 and secondary_reset <= now
    primary_bucket_current = primary_reset > now
    secondary_bucket_current = secondary_reset > now

    snapshot["snapshot_now_epoch"] = now
    snapshot["snapshot_event_epoch"] = event_epoch
    snapshot["snapshot_age_seconds"] = None if event_epoch is None else max(0, now - event_epoch)
    snapshot["primary_reset_age_seconds"] = None if primary_reset <= 0 else now - primary_reset
    snapshot["secondary_reset_age_seconds"] = None if secondary_reset <= 0 else now - secondary_reset
    snapshot["primary_reset_expired"] = primary_reset_expired
    snapshot["secondary_reset_expired"] = secondary_reset_expired
    snapshot["primary_bucket_current"] = primary_bucket_current
    snapshot["secondary_bucket_current"] = secondary_bucket_current
    snapshot["snapshot_stale_after_reset"] = primary_reset_expired or secondary_reset_expired
    return snapshot


def latest_quota_snapshot(items, now):
    # Always evaluate the newest token-count event. Bucket freshness is tracked
    # separately so one expired reset window cannot hide a newer current bucket.
    if not items:
        return None, False
    latest = items[-1]
    snapshot_has_current_bucket = (
        latest.get("primary_resets_at", 0) > now or latest.get("secondary_resets_at", 0) > now
    )
    return latest, snapshot_has_current_bucket


def snapshot_for_target_model(items, model, now):
    filtered, selection = snapshots_for_target_model(items, model)
    snapshot, snapshot_is_current = latest_quota_snapshot(filtered, now)
    if snapshot is None:
        return None, selection, 0, False
    return annotate_snapshot_freshness(dict(snapshot), now), selection, len(filtered), snapshot_is_current


def last_positive_delta_from_log(path: Path, model: str):
    # Recent successful cycles tell us what "one more run" usually costs for
    # this model. Failed or missing-marker cycles are deliberately ignored so an
    # incident does not poison the next projection.
    if not path.exists():
        return None, None
    cycle_models = {}
    primary = None
    secondary = None
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as handle:
            for raw_line in handle:
                cycle_match = cycle_re.search(raw_line)
                cycle_id = cycle_match.group(1) if cycle_match else None
                start_model_match = start_model_re.search(raw_line)
                if cycle_id and start_model_match:
                    cycle_models[cycle_id] = start_model_match.group(1)
                match = summary_re.search(raw_line)
                if not match:
                    continue
                summary_model_match = summary_model_re.search(raw_line)
                summary_model = None
                if summary_model_match:
                    summary_model = summary_model_match.group(1)
                elif cycle_id:
                    summary_model = cycle_models.get(cycle_id)
                if model and summary_model and summary_model != model:
                    continue
                status_marker = match.group(3)
                codex_exit = int(match.group(4))
                if codex_exit != 0 or status_marker == "missing":
                    continue
                primary_delta = float(match.group(1))
                secondary_delta = float(match.group(2))
                if primary_delta <= 0.0 and secondary_delta <= 0.0:
                    continue
                primary = primary_delta
                secondary = secondary_delta
    except OSError:
        return None, None
    return primary, secondary


try:
    snapshots = parse_session_snapshots(codex_home, scan_limit)
    now_epoch = int(time.time())
    snapshot, snapshot_selection, matching_snapshot_count, snapshot_is_current = snapshot_for_target_model(
        snapshots,
        target_model,
        now_epoch,
    )
    if snapshot is None:
        print(json.dumps({"error": "no_rate_limit_snapshot_found"}))
        sys.exit(0)

    log_primary, log_secondary = last_positive_delta_from_log(log_path, target_model)
    if log_primary is not None and log_secondary is not None:
        primary_delta = log_primary
        secondary_delta = log_secondary
        basis = "log_summary"
    else:
        primary_delta = 1.0
        secondary_delta = 1.0
        basis = "default_1_percent"

    print(
        json.dumps(
            {
                "snapshot": snapshot,
                "snapshot_selection": snapshot_selection,
                "snapshot_is_current": snapshot_is_current,
                "matching_snapshot_count": matching_snapshot_count,
                "target_model": target_model,
                "projection": {
                    "primary_delta": primary_delta,
                    "secondary_delta": secondary_delta,
                    "basis": basis,
                },
            }
        )
    )
except KeyboardInterrupt:
    print(json.dumps({"error": "interrupted"}))
    sys.exit(0)
PY
}
