#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <output-artifacts-dir> <target=run-dir-or-file> [target=run-dir-or-file ...]"
  echo "example: $0 artifacts \
  rust-axum=bench/results/rust-axum/20260508-190000 \
  go-fiber=bench/results/go-fiber/20260508-191000 \
  dotnet-jit=bench/results/dotnet-jit/20260508-192000"
  exit 1
fi

OUTPUT_DIR="$1"
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ "$OUTPUT_DIR" = /* ]]; then
  RESOLVED_OUTPUT_DIR="$OUTPUT_DIR"
else
  RESOLVED_OUTPUT_DIR="$PROJECT_ROOT/$OUTPUT_DIR"
fi

mkdir -p "$RESOLVED_OUTPUT_DIR"

INPUT_JSON_FILES=()

for pair in "$@"; do
  if [[ "$pair" != *=* ]]; then
    echo "invalid target mapping: $pair"
    echo "expected format: target=run-dir-or-file"
    exit 1
  fi

  target="${pair%%=*}"
  path_raw="${pair#*=}"

  if [[ "$path_raw" = /* ]]; then
    path_resolved="$path_raw"
  else
    path_resolved="$PROJECT_ROOT/$path_raw"
  fi

  if [ -d "$path_resolved" ]; then
    candidate="$path_resolved/benchmark-results-v2.json"
  else
    candidate="$path_resolved"
  fi

  if [ ! -f "$candidate" ]; then
    echo "missing benchmark-results-v2.json for target '$target' at: $candidate"
    exit 1
  fi

  INPUT_JSON_FILES+=("$target=$candidate")
done

python3 - "$RESOLVED_OUTPUT_DIR" "${INPUT_JSON_FILES[@]}" <<'PY'
import json
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path


def metric_from_measurements(measurements, phase, concurrency, key_path):
    for m in measurements:
        if m.get("phase") != phase:
            continue
        if m.get("concurrency") != concurrency:
            continue

        value = m
        for part in key_path:
            if not isinstance(value, dict):
                return None
            value = value.get(part)
        return value
    return None


def safe_mean(values):
    numeric = [v for v in values if isinstance(v, (int, float))]
    if not numeric:
        return None
    return statistics.mean(numeric)


output_dir = Path(sys.argv[1])
input_pairs = sys.argv[2:]

loaded = []

for pair in input_pairs:
    target, path_str = pair.split("=", 1)
    p = Path(path_str)
    payload = json.loads(p.read_text(encoding="utf-8"))
    loaded.append(
        {
            "target": target,
            "source_file": str(p),
            "payload": payload,
        }
    )

targets = [entry["target"] for entry in loaded]

summary_rows = []
for entry in loaded:
    target = entry["target"]
    payload = entry["payload"]
    baseline = payload.get("wrk_baseline", {})
    measurements = baseline.get("measurements", [])
    k6_tail = payload.get("k6_tail_latency", {})
    k6_pool = payload.get("k6_pool_saturation_recovery", {})

    row = {
        "target": target,
        "read_rps_c50": metric_from_measurements(measurements, "read", 50, ["requests_sec"]),
        "read_rps_c200": metric_from_measurements(measurements, "read", 200, ["requests_sec"]),
        "read_rps_c500": metric_from_measurements(measurements, "read", 500, ["requests_sec"]),
        "read_p99_ms_c200": metric_from_measurements(measurements, "read", 200, ["latency", "p99_ms"]),
        "write_rps_c50": metric_from_measurements(measurements, "write", 50, ["requests_sec"]),
        "tail_p95_ms": k6_tail.get("http_req_duration_ms", {}).get("p95"),
        "tail_p99_ms": k6_tail.get("http_req_duration_ms", {}).get("p99"),
        "tail_p999_ms": k6_tail.get("http_req_duration_ms", {}).get("p999"),
        "tail_failed_rate": k6_tail.get("http_req_failed_rate"),
        "tail_dropped_iterations_rate": k6_tail.get("dropped_iterations_rate"),
        "pool_p99_ms": k6_pool.get("http_req_duration_ms", {}).get("p99"),
        "pool_failed_rate": k6_pool.get("http_req_failed_rate"),
        "pool_dropped_iterations_rate": k6_pool.get("dropped_iterations_rate"),
    }
    summary_rows.append(row)

benchmark_results = {
    "schema_version": "benchmark-results-v2-aggregate-1",
    "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "targets": targets,
    "summary_rows": summary_rows,
    "runs": loaded,
}


def chart_series(metric_key):
    return [
        {
            "target": row["target"],
            "value": row.get(metric_key),
        }
        for row in summary_rows
    ]


charts_data = {
    "schema_version": "charts-data-v2-1",
    "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "targets": targets,
    "global_notes": {
        "tail_latency_p99_mean_ms": safe_mean([row.get("tail_p99_ms") for row in summary_rows]),
        "tail_latency_p999_mean_ms": safe_mean([row.get("tail_p999_ms") for row in summary_rows]),
    },
    "charts": [
        {
            "type": "grouped-bar",
            "title": "Read Throughput Across Concurrency Levels (RPS)",
            "groups": ["c=50", "c=200", "c=500"],
            "lower_is_better": False,
            "series": [
                {
                    "target": row["target"],
                    "values": [row.get("read_rps_c50"), row.get("read_rps_c200"), row.get("read_rps_c500")],
                }
                for row in summary_rows
            ],
        },
        {
            "type": "bar",
            "title": "Read Tail Latency p99 (wrk, c=200)",
            "lower_is_better": True,
            "series": chart_series("read_p99_ms_c200"),
        },
        {
            "type": "bar",
            "title": "Tail Latency p99 (k6 open-loop)",
            "lower_is_better": True,
            "series": chart_series("tail_p99_ms"),
        },
        {
            "type": "bar",
            "title": "Tail Latency p99.9 (k6 open-loop)",
            "lower_is_better": True,
            "series": chart_series("tail_p999_ms"),
        },
        {
            "type": "bar",
            "title": "Dropped Iterations Rate (k6 open-loop)",
            "lower_is_better": True,
            "series": chart_series("tail_dropped_iterations_rate"),
        },
        {
            "type": "bar",
            "title": "Saturation Recovery p99 (k6 ramping-vus)",
            "lower_is_better": True,
            "series": chart_series("pool_p99_ms"),
        },
        {
            "type": "bar",
            "title": "Write Throughput (wrk POST /users c=50)",
            "lower_is_better": False,
            "series": chart_series("write_rps_c50"),
        },
    ],
}

benchmark_out = output_dir / "benchmark-results-v2.json"
charts_out = output_dir / "charts-data-v2.json"

benchmark_out.write_text(json.dumps(benchmark_results, indent=2), encoding="utf-8")
charts_out.write_text(json.dumps(charts_data, indent=2), encoding="utf-8")

print(f"wrote {benchmark_out}")
print(f"wrote {charts_out}")
PY
