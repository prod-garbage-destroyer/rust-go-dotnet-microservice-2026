#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "usage: $0 <target-name> <scenario-name> <summary-json> <output-json>"
  echo "example: $0 rust-axum tail-latency bench/results/rust-axum/20260508-120000/k6-tail-summary.json bench/results/rust-axum/20260508-120000/k6-tail-normalized.json"
  exit 1
fi

TARGET_NAME="$1"
SCENARIO_NAME="$2"
SUMMARY_JSON="$3"
OUTPUT_JSON="$4"

mkdir -p "$(dirname "$OUTPUT_JSON")"

python3 - "$TARGET_NAME" "$SCENARIO_NAME" "$SUMMARY_JSON" "$OUTPUT_JSON" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

target = sys.argv[1]
scenario = sys.argv[2]
summary_path = Path(sys.argv[3])
output_path = Path(sys.argv[4])

payload = json.loads(summary_path.read_text(encoding="utf-8"))
metrics = payload.get("metrics", {})


def metric_values(name: str):
    metric = metrics.get(name, {})
    if not isinstance(metric, dict):
        return {}

    values = metric.get("values")
    if isinstance(values, dict):
        return values

    fallback = {}
    for key in (
        "avg",
        "min",
        "med",
        "max",
        "count",
        "rate",
        "value",
        "p(90)",
        "p(95)",
        "p(99)",
        "p(99.9)",
    ):
        if key in metric:
            fallback[key] = metric.get(key)
    return fallback


def metric_thresholds(name: str):
    return metrics.get(name, {}).get("thresholds", {})


http_duration = metric_values("http_req_duration")
http_failed_values = metric_values("http_req_failed")
http_failed_metric = metrics.get("http_req_failed", {})
iterations = metric_values("iterations")
dropped = metric_values("dropped_iterations")
vus = metric_values("vus")
vus_max = metric_values("vus_max")

failed_rate = http_failed_values.get("rate")
if failed_rate is None:
    failed_rate = http_failed_metric.get("value")

if failed_rate is None:
    # Last-resort fallback for older/irregular summaries where value/rate is absent.
    passes = http_failed_metric.get("passes")
    fails = http_failed_metric.get("fails")
    if isinstance(passes, (int, float)) and isinstance(fails, (int, float)) and (passes + fails) > 0:
        failed_rate = fails / (passes + fails)

result = {
    "schema_version": "k6-normalized-1",
    "target": target,
    "scenario": scenario,
    "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "source_summary_file": str(summary_path),
    "checks": {
        "passes": payload.get("root_group", {}).get("checks", []),
    },
    "http_req_duration_ms": {
        "avg": http_duration.get("avg"),
        "min": http_duration.get("min"),
        "med": http_duration.get("med"),
        "max": http_duration.get("max"),
        "p90": http_duration.get("p(90)"),
        "p95": http_duration.get("p(95)"),
        "p99": http_duration.get("p(99)"),
        "p999": http_duration.get("p(99.9)"),
    },
    "http_req_failed_rate": failed_rate,
    "iteration_rate": iterations.get("rate"),
    "iteration_count": iterations.get("count"),
    "dropped_iterations_rate": dropped.get("rate"),
    "dropped_iterations_count": dropped.get("count"),
    "vus": {
        "current": vus.get("value"),
        "max": vus_max.get("value"),
    },
    "thresholds": {
        "http_req_duration": metric_thresholds("http_req_duration"),
        "http_req_failed": metric_thresholds("http_req_failed"),
    },
    "raw_metrics": metrics,
}

output_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
print(f"wrote normalized k6 metrics: {output_path}")
PY
