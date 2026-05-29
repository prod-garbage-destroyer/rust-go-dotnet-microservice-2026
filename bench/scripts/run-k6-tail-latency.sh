#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <target-name> <base-url> <seeded-user-ids-comma-separated> [output-root]"
  echo "example: $0 rust-axum http://localhost:3001 11111111-1111-1111-1111-111111111111"
  exit 1
fi

TARGET_NAME="$1"
BASE_URL="$2"
BENCH_USER_IDS="$3"
OUTPUT_ROOT="${4:-bench/results}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$PROJECT_ROOT/$OUTPUT_ROOT/$TARGET_NAME/$TIMESTAMP"
mkdir -p "$RUN_DIR"

SUMMARY_JSON="$RUN_DIR/k6-tail-summary.json"
NORMALIZED_JSON="$RUN_DIR/k6-tail-normalized.json"

BASE_URL="$BASE_URL" \
BENCH_USER_IDS="$BENCH_USER_IDS" \
k6 run \
  --summary-export "$SUMMARY_JSON" \
  "$PROJECT_ROOT/bench/k6/tail-latency.js" | tee "$RUN_DIR/k6-tail-stdout.log"

"$PROJECT_ROOT/bench/scripts/collect-k6-metrics.sh" \
  "$TARGET_NAME" \
  "tail-latency" \
  "$SUMMARY_JSON" \
  "$NORMALIZED_JSON"

echo "k6 tail-latency outputs: $RUN_DIR"
