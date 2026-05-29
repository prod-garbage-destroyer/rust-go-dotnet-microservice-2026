#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <target-name> <run-dir> <output-json>"
  echo "example: $0 rust-axum bench/results/rust-axum/20260508-120000 artifacts/run.json"
  exit 1
fi

TARGET_NAME="$1"
RUN_DIR="$2"
OUTPUT_JSON="$3"

mkdir -p "$(dirname "$OUTPUT_JSON")"

python3 - "$TARGET_NAME" "$RUN_DIR" "$OUTPUT_JSON" <<'PY'
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

target_name = sys.argv[1]
run_dir = Path(sys.argv[2])
output_json = Path(sys.argv[3])

specs = [
    ("warmup", "GET /health", 50, 10, "warmup-health.txt"),
    ("read", "GET /users/:id", 50, 30, "read-c50.txt"),
    ("read", "GET /users/:id", 200, 30, "read-c200.txt"),
    ("read", "GET /users/:id", 500, 30, "read-c500.txt"),
    ("write", "POST /users", 50, 20, "write-c50.txt"),
]


def to_number(raw: str):
    if not raw:
        return None
    m = re.match(r"^([0-9]+(?:\.[0-9]+)?)([kKmMgG]?)$", raw.strip())
    if not m:
        return None
    num = float(m.group(1))
    suffix = m.group(2).lower()
    scale = {"": 1, "k": 1_000, "m": 1_000_000, "g": 1_000_000_000}[suffix]
    return num * scale


def to_ms(raw: str):
    if not raw:
        return None
    m = re.match(r"^([0-9]+(?:\.[0-9]+)?)(us|ms|s|m)?$", raw.strip())
    if not m:
        return None
    num = float(m.group(1))
    unit = m.group(2) or "ms"
    if unit == "us":
        return num / 1000
    if unit == "ms":
        return num
    if unit == "s":
        return num * 1000
    if unit == "m":
        return num * 60000
    return None


def first_match(pattern: str, text: str):
    m = re.search(pattern, text, flags=re.MULTILINE)
    if not m:
        return None
    return m.group(1)


measurements = []

for phase, endpoint, concurrency, duration_seconds, file_name in specs:
    p = run_dir / file_name
    if not p.exists():
        continue

    text = p.read_text(encoding="utf-8", errors="replace")

    latency_line = first_match(r"^\s*Latency\s+(.+)$", text)
    lat_avg = lat_stdev = lat_max = None
    if latency_line:
        parts = latency_line.split()
        if len(parts) >= 3:
            lat_avg = to_ms(parts[0])
            lat_stdev = to_ms(parts[1])
            lat_max = to_ms(parts[2])

    p50 = to_ms(first_match(r"^\s*50%\s+([0-9.]+(?:us|ms|s|m)?)\s*$", text) or "")
    p75 = to_ms(first_match(r"^\s*75%\s+([0-9.]+(?:us|ms|s|m)?)\s*$", text) or "")
    p90 = to_ms(first_match(r"^\s*90%\s+([0-9.]+(?:us|ms|s|m)?)\s*$", text) or "")
    p99 = to_ms(first_match(r"^\s*99%\s+([0-9.]+(?:us|ms|s|m)?)\s*$", text) or "")

    req_sec = to_number(first_match(r"^Requests/sec:\s+([0-9.]+[kKmMgG]?)\s*$", text) or "")
    transfer_token = first_match(r"^Transfer/sec:\s+([0-9.]+[kKmMgG]?[A-Za-z]*)\s*$", text) or ""

    transfer_bytes = None
    tm = re.match(r"^([0-9]+(?:\.[0-9]+)?)([kKmMgG]?)(B|KB|MB|GB)?$", transfer_token)
    if tm:
        num = float(tm.group(1))
        suffix = (tm.group(2) or "").lower()
        unit = (tm.group(3) or "B").upper()
        unit_scale = {"B": 1, "KB": 1024, "MB": 1024 ** 2, "GB": 1024 ** 3}.get(unit, 1)
        short_scale = {"": 1, "k": 1024, "m": 1024 ** 2, "g": 1024 ** 3}.get(suffix, 1)
        transfer_bytes = num * max(unit_scale, short_scale)

    non2xx_raw = first_match(r"^Non-2xx or 3xx responses:\s+([0-9]+)\s*$", text)
    non2xx = int(non2xx_raw) if non2xx_raw else 0

    measurements.append(
        {
            "phase": phase,
            "endpoint": endpoint,
            "concurrency": concurrency,
            "duration_seconds": duration_seconds,
            "requests_sec": req_sec,
            "transfer_sec_bytes": transfer_bytes,
            "latency": {
                "avg_ms": lat_avg,
                "stdev_ms": lat_stdev,
                "max_ms": lat_max,
                "p50_ms": p50,
                "p75_ms": p75,
                "p90_ms": p90,
                "p99_ms": p99,
            },
            "non_2xx_3xx_responses": non2xx,
            "raw_output_file": str(p),
        }
    )

payload = {
    "schema_version": "v2-baseline-1",
    "target": target_name,
    "run_dir": str(run_dir),
    "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "measurements": measurements,
}

output_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")
print(f"wrote metrics JSON: {output_json}")
PY
