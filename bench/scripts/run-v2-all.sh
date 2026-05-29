#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <target-name> <base-url> <seeded-user-ids-comma-separated> [output-root] [run-id]"
  echo "example: $0 rust-axum http://localhost:3001 11111111-1111-1111-1111-111111111111"
  exit 1
fi

TARGET_NAME="$1"
BASE_URL="$2"
BENCH_USER_IDS="$3"
OUTPUT_ROOT="${4:-bench/results}"
RUN_ID="${5:-$(date +%Y%m%d-%H%M%S)}"
USE_PODMAN_BENCH="${USE_PODMAN_BENCH:-false}"
PODMAN_WRK_IMAGE="${PODMAN_WRK_IMAGE:-auto}"
PODMAN_K6_IMAGE="${PODMAN_K6_IMAGE:-docker.io/grafana/k6:latest}"
PODMAN_WRK_CONTAINERFILE="${PODMAN_WRK_CONTAINERFILE:-bench/podman/wrk/Containerfile}"
PODMAN_WRK_LOCAL_IMAGE="${PODMAN_WRK_LOCAL_IMAGE:-local/bench-wrk:arm64}"
K6_ALLOW_THRESHOLD_FAILURE="${K6_ALLOW_THRESHOLD_FAILURE:-true}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUN_DIR="$PROJECT_ROOT/$OUTPUT_ROOT/$TARGET_NAME/$RUN_ID"
mkdir -p "$RUN_DIR"

if [ "$USE_PODMAN_BENCH" = "true" ] && [ "$PODMAN_WRK_IMAGE" = "auto" ]; then
  if [[ "$PODMAN_WRK_CONTAINERFILE" = /* ]]; then
    WRK_CONTAINERFILE_PATH="$PODMAN_WRK_CONTAINERFILE"
  else
    WRK_CONTAINERFILE_PATH="$PROJECT_ROOT/$PODMAN_WRK_CONTAINERFILE"
  fi

  if [ ! -f "$WRK_CONTAINERFILE_PATH" ]; then
    echo "wrk containerfile not found: $WRK_CONTAINERFILE_PATH"
    exit 1
  fi

  echo "[podman] building local arm64 wrk image: $PODMAN_WRK_LOCAL_IMAGE"
  podman build --platform linux/arm64 -t "$PODMAN_WRK_LOCAL_IMAGE" -f "$WRK_CONTAINERFILE_PATH" "$PROJECT_ROOT" >/dev/null
  PODMAN_WRK_IMAGE="$PODMAN_WRK_LOCAL_IMAGE"
fi

to_container_path() {
  local host_path="$1"
  if [[ "$host_path" == "$PROJECT_ROOT" ]]; then
    echo "/work"
    return
  fi
  if [[ "$host_path" == "$PROJECT_ROOT"/* ]]; then
    echo "/work/${host_path#$PROJECT_ROOT/}"
    return
  fi
  echo "$host_path"
}

TOOL_BASE_URL="$BASE_URL"
if [ "$USE_PODMAN_BENCH" = "true" ]; then
  TOOL_BASE_URL="${TOOL_BASE_URL/localhost/host.containers.internal}"
  TOOL_BASE_URL="${TOOL_BASE_URL/127.0.0.1/host.containers.internal}"
fi

run_wrk() {
  if [ "$USE_PODMAN_BENCH" = "true" ]; then
    podman run --rm -i --platform linux/arm64 -v "$PROJECT_ROOT:/work" -w /work "$PODMAN_WRK_IMAGE" "$@"
  else
    wrk "$@"
  fi
}

run_k6() {
  local summary_path="$1"
  local script_path="$2"
  if [ "$USE_PODMAN_BENCH" = "true" ]; then
    local summary_container script_container
    summary_container="$(to_container_path "$summary_path")"
    script_container="$(to_container_path "$script_path")"
    podman run --rm -i -v "$PROJECT_ROOT:/work" -w /work \
      --platform linux/arm64 \
      -e BASE_URL="$TOOL_BASE_URL" \
      -e BENCH_USER_IDS="$BENCH_USER_IDS" \
      "$PODMAN_K6_IMAGE" run --summary-export "$summary_container" "$script_container"
  else
    BASE_URL="$TOOL_BASE_URL" \
    BENCH_USER_IDS="$BENCH_USER_IDS" \
    k6 run --summary-export "$summary_path" "$script_path"
  fi
}

WRK_GET_SCRIPT="$PROJECT_ROOT/bench/wrk/get-users.lua"
WRK_POST_SCRIPT="$PROJECT_ROOT/bench/wrk/post-users.lua"
if [ "$USE_PODMAN_BENCH" = "true" ]; then
  WRK_GET_SCRIPT="$(to_container_path "$WRK_GET_SCRIPT")"
  WRK_POST_SCRIPT="$(to_container_path "$WRK_POST_SCRIPT")"
fi

export BENCH_USER_IDS
export BENCH_NOTIFY_LOG="false"

run_and_capture() {
  local label="$1"
  local file_name="$2"
  shift 2

  echo "$label"
  "$@" | tee "$RUN_DIR/$file_name"
}

echo "target: $TARGET_NAME"
echo "base-url: $BASE_URL"
echo "tool-base-url: $TOOL_BASE_URL"
echo "run-dir: $RUN_DIR"
echo "use-podman-bench: $USE_PODMAN_BENCH"
echo "k6-allow-threshold-failure: $K6_ALLOW_THRESHOLD_FAILURE"

run_and_capture "[warmup] GET /health c=50 d=10s" "warmup-health.txt" \
  run_wrk -c 50 -d 10s -t 4 "$TOOL_BASE_URL/health"

run_and_capture "[warmup] GET /users/:id c=50 d=10s" "warmup-read.txt" \
  run_wrk -c 50 -d 10s -t 8 -s "$WRK_GET_SCRIPT" "$TOOL_BASE_URL"

run_and_capture "[warmup] POST /users c=50 d=10s" "warmup-write.txt" \
  run_wrk -c 50 -d 10s -t 4 -s "$WRK_POST_SCRIPT" "$TOOL_BASE_URL"

run_and_capture "[read] GET /users/:id c=50 d=30s" "read-c50.txt" \
  run_wrk -c 50 -d 30s -t 8 -s "$WRK_GET_SCRIPT" "$TOOL_BASE_URL"

run_and_capture "[read] GET /users/:id c=200 d=30s" "read-c200.txt" \
  run_wrk -c 200 -d 30s -t 8 -s "$WRK_GET_SCRIPT" "$TOOL_BASE_URL"

run_and_capture "[read] GET /users/:id c=500 d=30s" "read-c500.txt" \
  run_wrk -c 500 -d 30s -t 8 -s "$WRK_GET_SCRIPT" "$TOOL_BASE_URL"

run_and_capture "[write] POST /users c=50 d=20s" "write-c50.txt" \
  run_wrk -c 50 -d 20s -t 4 -s "$WRK_POST_SCRIPT" "$TOOL_BASE_URL"

"$PROJECT_ROOT/bench/scripts/collect-metrics.sh" \
  "$TARGET_NAME" \
  "$RUN_DIR" \
  "$RUN_DIR/benchmark-results.json"

echo "[k6] tail-latency"
set +e
run_k6 "$RUN_DIR/k6-tail-summary.json" "$PROJECT_ROOT/bench/k6/tail-latency.js" | tee "$RUN_DIR/k6-tail-stdout.log"
K6_TAIL_EXIT_CODE=$?
set -e
if [ "$K6_TAIL_EXIT_CODE" -ne 0 ]; then
  if [ "$K6_ALLOW_THRESHOLD_FAILURE" = "true" ]; then
    echo "[warn] k6 tail-latency exited with code $K6_TAIL_EXIT_CODE; continuing due to K6_ALLOW_THRESHOLD_FAILURE=true"
  else
    echo "[error] k6 tail-latency exited with code $K6_TAIL_EXIT_CODE"
    exit "$K6_TAIL_EXIT_CODE"
  fi
fi

"$PROJECT_ROOT/bench/scripts/collect-k6-metrics.sh" \
  "$TARGET_NAME" \
  "tail-latency" \
  "$RUN_DIR/k6-tail-summary.json" \
  "$RUN_DIR/k6-tail-normalized.json"

echo "[k6] pool-saturation-recovery"
set +e
run_k6 "$RUN_DIR/k6-pool-saturation-summary.json" "$PROJECT_ROOT/bench/k6/scenarios/pool-saturation-recovery.js" | tee "$RUN_DIR/k6-pool-saturation-stdout.log"
K6_POOL_EXIT_CODE=$?
set -e
if [ "$K6_POOL_EXIT_CODE" -ne 0 ]; then
  if [ "$K6_ALLOW_THRESHOLD_FAILURE" = "true" ]; then
    echo "[warn] k6 pool-saturation-recovery exited with code $K6_POOL_EXIT_CODE; continuing due to K6_ALLOW_THRESHOLD_FAILURE=true"
  else
    echo "[error] k6 pool-saturation-recovery exited with code $K6_POOL_EXIT_CODE"
    exit "$K6_POOL_EXIT_CODE"
  fi
fi

"$PROJECT_ROOT/bench/scripts/collect-k6-metrics.sh" \
  "$TARGET_NAME" \
  "pool-saturation-recovery" \
  "$RUN_DIR/k6-pool-saturation-summary.json" \
  "$RUN_DIR/k6-pool-saturation-normalized.json"

python3 - "$TARGET_NAME" "$RUN_DIR" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

target = sys.argv[1]
run_dir = Path(sys.argv[2])

baseline = json.loads((run_dir / "benchmark-results.json").read_text(encoding="utf-8"))
tail = json.loads((run_dir / "k6-tail-normalized.json").read_text(encoding="utf-8"))
pool = json.loads((run_dir / "k6-pool-saturation-normalized.json").read_text(encoding="utf-8"))

merged = {
    "schema_version": "benchmark-results-v2-1",
    "target": target,
    "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "run_dir": str(run_dir),
    "inputs": {
        "wrk": "benchmark-results.json",
        "k6_tail": "k6-tail-normalized.json",
        "k6_pool_saturation_recovery": "k6-pool-saturation-normalized.json",
    },
    "wrk_baseline": baseline,
    "k6_tail_latency": tail,
    "k6_pool_saturation_recovery": pool,
}

out_file = run_dir / "benchmark-results-v2.json"
out_file.write_text(json.dumps(merged, indent=2), encoding="utf-8")
print(f"wrote merged v2 benchmark JSON: {out_file}")
PY

echo "all outputs: $RUN_DIR"
