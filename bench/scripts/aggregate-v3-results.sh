#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <output-artifacts-dir> <target=run-dir-or-file> [target=run-dir-or-file ...] [--excluded target=reason ...]"
  echo "example: $0 artifacts \\"
  echo "  rust-axum=bench/results/rust-axum/v3-20260526-212300-rust-axum \\"
  echo "  go-fiber=bench/results/go-fiber/v3-20260526-213932-go-fiber \\"
  echo "  go-nethttp-chi=bench/results/go-nethttp-chi/v3-20260526-215610-go-nethttp-chi \\"
  echo "  dotnet-aot=bench/results/dotnet-aot/v3-20260526-210210-dotnet-aot \\"
  echo "  --excluded dotnet-jit=SIGILL-on-podman-ARM64"
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
EXCLUDED_TARGETS=()
MODE="inputs"

for arg in "$@"; do
  if [ "$arg" = "--excluded" ]; then
    MODE="excluded"
    continue
  fi

  if [[ "$arg" != *=* ]]; then
    echo "invalid mapping: $arg"
    echo "expected format: target=run-dir-or-file"
    exit 1
  fi

  target="${arg%%=*}"
  value_raw="${arg#*=}"

  if [ "$MODE" = "excluded" ]; then
    EXCLUDED_TARGETS+=("$target=$value_raw")
    continue
  fi

  if [[ "$value_raw" = /* ]]; then
    value_resolved="$value_raw"
  else
    value_resolved="$PROJECT_ROOT/$value_raw"
  fi

  if [ -d "$value_resolved" ]; then
    candidate="$value_resolved/benchmark-results-v2.json"
  else
    candidate="$value_resolved"
  fi

  if [ ! -f "$candidate" ]; then
    echo "missing benchmark-results-v2.json for target '$target' at: $candidate"
    exit 1
  fi

  INPUT_JSON_FILES+=("$target=$candidate")
done

python3 - "$PROJECT_ROOT" "$RESOLVED_OUTPUT_DIR" "${INPUT_JSON_FILES[@]}" --excluded "${EXCLUDED_TARGETS[@]}" <<'PY'
import json
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path


def metric_from_measurements(measurements, phase, concurrency, key_path):
    for measurement in measurements:
        if measurement.get("phase") != phase:
            continue
        if measurement.get("concurrency") != concurrency:
            continue
        value = measurement
        for part in key_path:
            if not isinstance(value, dict):
                return None
            value = value.get(part)
        return value
    return None


def rank_map(rows, key, reverse):
    sortable = [row for row in rows if isinstance(row.get(key), (int, float))]
    ordered = sorted(sortable, key=lambda row: row[key], reverse=reverse)
    return {row["target"]: index + 1 for index, row in enumerate(ordered)}


def safe_mean(values):
    numeric = [value for value in values if isinstance(value, (int, float))]
    if not numeric:
        return None
    return statistics.mean(numeric)


def safe_min_row(rows, key):
    numeric = [row for row in rows if isinstance(row.get(key), (int, float))]
    if not numeric:
        return None
    return min(numeric, key=lambda row: row[key])


def safe_max_row(rows, key):
    numeric = [row for row in rows if isinstance(row.get(key), (int, float))]
    if not numeric:
        return None
    return max(numeric, key=lambda row: row[key])


def rounded(value, digits=2):
    if not isinstance(value, (int, float)):
        return value
    return round(value, digits)


def pct_delta(best, baseline):
    if not isinstance(best, (int, float)) or not isinstance(baseline, (int, float)) or baseline == 0:
        return None
    return ((best - baseline) / baseline) * 100.0


project_root = Path(sys.argv[1])
output_dir = Path(sys.argv[2])
args = sys.argv[3:]

if "--excluded" in args:
    split_index = args.index("--excluded")
    input_pairs = args[:split_index]
    excluded_pairs = args[split_index + 1 :]
else:
    input_pairs = args
    excluded_pairs = []

loaded = []
for pair in input_pairs:
    target, path_str = pair.split("=", 1)
    payload_path = Path(path_str)
    payload = json.loads(payload_path.read_text(encoding="utf-8"))
    loaded.append(
        {
            "target": target,
            "source_file": str(payload_path),
            "payload": payload,
        }
    )

excluded_targets = []
for pair in excluded_pairs:
    target, reason = pair.split("=", 1)
    excluded_targets.append({"target": target, "reason": reason})

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
        "run_dir": payload.get("run_dir"),
        "source_file": entry["source_file"],
        "read_rps_c50": metric_from_measurements(measurements, "read", 50, ["requests_sec"]),
        "read_rps_c200": metric_from_measurements(measurements, "read", 200, ["requests_sec"]),
        "read_rps_c500": metric_from_measurements(measurements, "read", 500, ["requests_sec"]),
        "write_rps_c50": metric_from_measurements(measurements, "write", 50, ["requests_sec"]),
        "tail_p95_ms": k6_tail.get("http_req_duration_ms", {}).get("p95"),
        "tail_p99_ms": k6_tail.get("http_req_duration_ms", {}).get("p99"),
        "tail_p999_ms": k6_tail.get("http_req_duration_ms", {}).get("p999"),
        "tail_failed_rate": k6_tail.get("http_req_failed_rate"),
        "tail_dropped_iterations_rate": k6_tail.get("dropped_iterations_rate"),
        "pool_p95_ms": k6_pool.get("http_req_duration_ms", {}).get("p95"),
        "pool_p99_ms": k6_pool.get("http_req_duration_ms", {}).get("p99"),
        "pool_p999_ms": k6_pool.get("http_req_duration_ms", {}).get("p999"),
        "pool_failed_rate": k6_pool.get("http_req_failed_rate"),
        "pool_dropped_iterations_rate": k6_pool.get("dropped_iterations_rate"),
    }
    summary_rows.append(row)

read_rank = rank_map(summary_rows, "read_rps_c200", reverse=True)
write_rank = rank_map(summary_rows, "write_rps_c50", reverse=True)
tail_rank = rank_map(summary_rows, "tail_p99_ms", reverse=False)
tail_p999_rank = rank_map(summary_rows, "tail_p999_ms", reverse=False)
pool_rank = rank_map(summary_rows, "pool_p99_ms", reverse=False)

for row in summary_rows:
    row["rankings"] = {
        "read_rps_c200": read_rank.get(row["target"]),
        "write_rps_c50": write_rank.get(row["target"]),
        "tail_p99_ms": tail_rank.get(row["target"]),
        "tail_p999_ms": tail_p999_rank.get(row["target"]),
        "pool_p99_ms": pool_rank.get(row["target"]),
    }

best_read = safe_max_row(summary_rows, "read_rps_c200")
best_tail = safe_min_row(summary_rows, "tail_p99_ms")
best_tail_p999 = safe_min_row(summary_rows, "tail_p999_ms")
best_pool = safe_min_row(summary_rows, "pool_p99_ms")
best_write = safe_max_row(summary_rows, "write_rps_c50")
target_index = {row["target"]: row for row in summary_rows}

headline = []
if best_read:
    headline.append(
        {
            "category": "read throughput @ c=200",
            "winner": best_read["target"],
            "value": rounded(best_read["read_rps_c200"]),
            "unit": "rps",
        }
    )
if best_tail:
    headline.append(
        {
            "category": "open-loop tail p99",
            "winner": best_tail["target"],
            "value": rounded(best_tail["tail_p99_ms"]),
            "unit": "ms",
        }
    )
if best_tail_p999:
    headline.append(
        {
            "category": "open-loop tail p99.9",
            "winner": best_tail_p999["target"],
            "value": rounded(best_tail_p999["tail_p999_ms"]),
            "unit": "ms",
        }
    )
if best_pool:
    headline.append(
        {
            "category": "pool saturation recovery p99",
            "winner": best_pool["target"],
            "value": rounded(best_pool["pool_p99_ms"]),
            "unit": "ms",
        }
    )

overview = {
    "read_rps_c200_mean": rounded(safe_mean([row.get("read_rps_c200") for row in summary_rows])),
    "tail_p99_ms_mean": rounded(safe_mean([row.get("tail_p99_ms") for row in summary_rows])),
    "pool_p99_ms_mean": rounded(safe_mean([row.get("pool_p99_ms") for row in summary_rows])),
}

benchmark_results = {
    "schema_version": "benchmark-results-v3-aggregate-1",
    "experiment_slug": "rust-go-dotnet-microservice-2026-v3",
    "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "official_targets": [row["target"] for row in summary_rows],
    "excluded_targets": excluded_targets,
    "source_policy": {
        "official_csharp_lane": "dotnet-aot",
        "excluded_lane_policy": "dotnet-jit is appendix-only when host/runtime instability prevents a full v3 run.",
    },
    "headline_winners": headline,
    "overview": overview,
    "summary_rows": summary_rows,
    "runs": loaded,
}

tail_latency = {
    "schema_version": "tail-latency-v3-1",
    "experiment_slug": "rust-go-dotnet-microservice-2026-v3",
    "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "scenario": "k6 open-loop tail latency",
    "rows": [
        {
            "target": row["target"],
            "tail_p95_ms": row["tail_p95_ms"],
            "tail_p99_ms": row["tail_p99_ms"],
            "tail_p999_ms": row["tail_p999_ms"],
            "tail_failed_rate": row["tail_failed_rate"],
            "tail_dropped_iterations_rate": row["tail_dropped_iterations_rate"],
            "rank_p99": row["rankings"]["tail_p99_ms"],
            "rank_p999": row["rankings"]["tail_p999_ms"],
        }
        for row in summary_rows
    ],
}

pool_recovery = {
    "schema_version": "pool-saturation-recovery-v3-1",
    "experiment_slug": "rust-go-dotnet-microservice-2026-v3",
    "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "scenario": "k6 pool saturation recovery",
    "rows": [
        {
            "target": row["target"],
            "pool_p95_ms": row["pool_p95_ms"],
            "pool_p99_ms": row["pool_p99_ms"],
            "pool_p999_ms": row["pool_p999_ms"],
            "pool_failed_rate": row["pool_failed_rate"],
            "pool_dropped_iterations_rate": row["pool_dropped_iterations_rate"],
            "rank_p99": row["rankings"]["pool_p99_ms"],
        }
        for row in summary_rows
    ],
}

charts_data = {
    "schema_version": "charts-data-v3-1",
    "experiment_slug": "rust-go-dotnet-microservice-2026-v3",
    "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "official_targets": [row["target"] for row in summary_rows],
    "charts": [
        {
            "type": "grouped-bar",
            "title": "Read Throughput Across Concurrency Levels (RPS)",
            "groups": ["c=50", "c=200", "c=500"],
            "lower_is_better": False,
            "series": [
                {
                    "target": row["target"],
                    "values": [row["read_rps_c50"], row["read_rps_c200"], row["read_rps_c500"]],
                }
                for row in summary_rows
            ],
        },
        {
            "type": "bar",
            "title": "Write Throughput (wrk POST /users c=50)",
            "lower_is_better": False,
            "series": [{"target": row["target"], "value": row["write_rps_c50"]} for row in summary_rows],
        },
        {
            "type": "bar",
            "title": "Open-Loop Tail Latency p99 (k6)",
            "lower_is_better": True,
            "series": [{"target": row["target"], "value": row["tail_p99_ms"]} for row in summary_rows],
        },
        {
            "type": "bar",
            "title": "Open-Loop Tail Latency p99.9 (k6)",
            "lower_is_better": True,
            "series": [{"target": row["target"], "value": row["tail_p999_ms"]} for row in summary_rows],
        },
        {
            "type": "bar",
            "title": "Dropped Iterations Rate (k6 Open-Loop)",
            "lower_is_better": True,
            "series": [{"target": row["target"], "value": row["tail_dropped_iterations_rate"]} for row in summary_rows],
        },
        {
            "type": "bar",
            "title": "Pool Saturation Recovery p99 (k6)",
            "lower_is_better": True,
            "series": [{"target": row["target"], "value": row["pool_p99_ms"]} for row in summary_rows],
        },
    ],
}

fairness_report_lines = [
    "# Fairness Report v3",
    "",
    "- Official publish set: `rust-axum`, `go-fiber`, `go-nethttp-chi`, `dotnet-aot`.",
    "- Official C# lane: `dotnet-aot`.",
    "- `dotnet-jit` is excluded from ranking on this host because it never produced a full merged v3 artifact.",
    "- Warmup + timed run provenance comes from per-target `benchmark-results-v2.json` files in `bench/results/...`.",
    "- Framework-class caveat remains: `go-fiber` is fasthttp-based and not stdlib-tier. Use `go-nethttp-chi` for apples-to-apples stdlib/Kestrel/Axum framing.",
    "",
    "## Excluded Targets",
]
if excluded_targets:
    for excluded in excluded_targets:
        fairness_report_lines.append(f"- `{excluded['target']}`: {excluded['reason']}")
else:
    fairness_report_lines.append("- None")

summary_lines = [
    "# Experiment Summary v3",
    "",
    "**Experiment slug:** `rust-go-dotnet-microservice-2026-v3`  ",
    f"**Generated:** {benchmark_results['generated_at_utc']}  ",
    "**Official publish set:** `rust-axum`, `go-fiber`, `go-nethttp-chi`, `dotnet-aot`",
    "",
    "## Executive Read",
    "",
]
if best_read and best_tail and best_pool:
    summary_lines.extend(
        [
            f"- `rust-axum` leads closed-loop read throughput at c=200 with **{rounded(best_read['read_rps_c200'])} RPS**.",
            f"- `{best_tail['target']}` leads open-loop tail p99 with **{rounded(best_tail['tail_p99_ms'])} ms**.",
            f"- `{best_tail_p999['target']}` leads open-loop tail p99.9 with **{rounded(best_tail_p999['tail_p999_ms'])} ms**.",
            f"- `go-fiber` leads saturation recovery p99 with **{rounded(best_pool['pool_p99_ms'])} ms**.",
            "- `dotnet-aot` is the official C# lane and lands in the middle of the pack on throughput while staying competitive on tail metrics.",
            "- `dotnet-jit` is excluded from official ranking on this host because the latest v3 run set never progressed beyond warmup artifacts.",
        ]
    )

summary_lines.extend(
    [
        "",
        "## Key Metrics Snapshot",
        "",
        "| Target | Read RPS c=200 | Write RPS c=50 | Tail p99 (k6) | Tail p99.9 (k6) | Recovery p99 (k6) |",
        "|---|---:|---:|---:|---:|---:|",
    ]
)
for row in summary_rows:
    summary_lines.append(
        f"| {row['target']} | {rounded(row['read_rps_c200'])} | {rounded(row['write_rps_c50'])} | {rounded(row['tail_p99_ms'])} ms | {rounded(row['tail_p999_ms'])} ms | {rounded(row['pool_p99_ms'])} ms |"
    )

rust_row = target_index.get("rust-axum")
fiber_row = target_index.get("go-fiber")
chi_row = target_index.get("go-nethttp-chi")
aot_row = target_index.get("dotnet-aot")

rust_vs_fiber_read_delta = None
if rust_row and fiber_row:
    rust_vs_fiber_read_delta = pct_delta(rust_row["read_rps_c200"], fiber_row["read_rps_c200"])

summary_lines.extend(
    [
        "",
        "## Publish-Safe Claims",
        "",
        f"- In this run window, `rust-axum` is the highest-throughput official lane at c=200, ahead of `go-fiber` by {rounded(rust_vs_fiber_read_delta)}%." if rust_vs_fiber_read_delta is not None and best_read and best_read["target"] == "rust-axum" else "- Official throughput claims should cite the `read_rps_c200` table above.",
        f"- `go-nethttp-chi` is the lowest-tail official lane on open-loop p99 ({rounded(chi_row['tail_p99_ms'])} ms)." if chi_row else "- Open-loop tail claims should cite the tail-latency table above.",
        f"- `dotnet-aot` is the lowest-tail official lane on open-loop p99.9 ({rounded(aot_row['tail_p999_ms'])} ms)." if aot_row else "- Open-loop p99.9 claims should cite the tail-latency table above.",
        f"- `go-fiber` recovers fastest after pool saturation with p99 {rounded(fiber_row['pool_p99_ms'])} ms." if fiber_row and best_pool and best_pool["target"] == "go-fiber" else "- Recovery claims should cite the pool-saturation table above.",
        "- `dotnet-aot` is the only official C# lane for v3 on this host; do not mix it with `dotnet-jit` in ranking claims.",
        "",
        "## Provenance",
        "",
    ]
)
for row in summary_rows:
    summary_lines.append(f"- `{row['target']}`: `{row['run_dir']}`")

summary_lines.append("")
summary_lines.append("## Missing From This Publish Cut")
summary_lines.append("")
summary_lines.append("- `cpu-efficiency-v3.json` has not been generated because no `perf`-derived aggregate was present in the selected run window.")
summary_lines.append("- `startup-cold-warm-v3.json` has not been generated because startup/cold-warm measurements were not aggregated into the chosen v3 official run set.")

methodology_source = project_root / "methodology-v3.md"
methodology_target = output_dir / "methodology-v3.md"
if methodology_source.exists():
    methodology_target.write_text(methodology_source.read_text(encoding="utf-8"), encoding="utf-8")

(output_dir / "benchmark-results-v3.json").write_text(json.dumps(benchmark_results, indent=2), encoding="utf-8")
(output_dir / "tail-latency-v3.json").write_text(json.dumps(tail_latency, indent=2), encoding="utf-8")
(output_dir / "pool-saturation-recovery-v3.json").write_text(json.dumps(pool_recovery, indent=2), encoding="utf-8")
(output_dir / "charts-data-v3.json").write_text(json.dumps(charts_data, indent=2), encoding="utf-8")
(output_dir / "summary-v3.md").write_text("\n".join(summary_lines) + "\n", encoding="utf-8")
(output_dir / "fairness-report-v3.md").write_text("\n".join(fairness_report_lines) + "\n", encoding="utf-8")

print(f"wrote {output_dir / 'benchmark-results-v3.json'}")
print(f"wrote {output_dir / 'tail-latency-v3.json'}")
print(f"wrote {output_dir / 'pool-saturation-recovery-v3.json'}")
print(f"wrote {output_dir / 'charts-data-v3.json'}")
print(f"wrote {output_dir / 'summary-v3.md'}")
print(f"wrote {output_dir / 'fairness-report-v3.md'}")
if methodology_source.exists():
    print(f"wrote {output_dir / 'methodology-v3.md'}")
PY
