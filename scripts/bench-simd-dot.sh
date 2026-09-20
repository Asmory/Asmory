#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="${ASMORY_BENCH_BIN:-./build/benchmarks/simd-dot-bench}"
OUT="${ASMORY_PERF_OUT:-./build/performance/simd-dot.json}"
SAMPLES="${ASMORY_PERF_SAMPLES:-11}"

mkdir -p "$(dirname "$OUT")"

[[ -x "$BIN" ]] || {
  echo "missing benchmark binary: $BIN" >&2
  exit 2
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

runner=("$BIN")
affinity="unbound"

# Do not parse `taskset -pc $$` human-readable output here.
# It is localized and may contain the PID before the CPU list.
#
# /proc/self/status exposes the kernel's actual cpuset restriction in a stable
# machine-oriented field:
#
#   Cpus_allowed_list:  0-11,16-23
#
# Pick the first allowed logical CPU. If pinning is unavailable or rejected,
# keep the benchmark runnable and record it as unbound.
if command -v taskset >/dev/null 2>&1 && [[ -r /proc/self/status ]]; then
  allowed="$(
    awk '/^Cpus_allowed_list:/ {
      sub(/^[^:]*:[[:space:]]*/, "", $0)
      print
      exit
    }' /proc/self/status
  )"

  first_range="${allowed%%,*}"
  cpu="${first_range%%-*}"

  if [[ "$cpu" =~ ^[0-9]+$ ]]; then
    if taskset -c "$cpu" true >/dev/null 2>&1; then
      runner=(taskset -c "$cpu" "$BIN")
      affinity="cpu:$cpu"
    else
      echo "warning: CPU $cpu is listed as allowed but taskset rejected pinning; continuing unbound" >&2
    fi
  fi
fi

echo "Asmory Performance Evidence"
echo "  benchmark: simd-dot/dot-f32-v1"
echo "  samples:   $SAMPLES"
echo "  affinity:  $affinity"
echo

for ((i=1; i<=SAMPLES; i++)); do
  "${runner[@]}" >"$tmp/$i.txt"
  grep -q '^correctness=pass$' "$tmp/$i.txt"

  printf '  sample %02d/%02d  %s ns\n' \
    "$i" "$SAMPLES" \
    "$(awk -F= '$1=="simd_total_ns"{print $2}' "$tmp/$i.txt")"
done

cpu_vendor="$(awk -F: '/vendor_id/{sub(/^[ \t]+/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null || true)"
cpu_model="$(awk -F: '/model name/{sub(/^[ \t]+/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null || true)"
microcode="$(awk -F: '/microcode/{sub(/^[ \t]+/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null || true)"
kernel="$(uname -srmo)"
governor="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)"

artifact="./build/packages/simd-dot-0.1.0.tar.gz"
if [[ -f "$artifact" ]]; then
  artifact_sha="$(sha256sum "$artifact" | awk '{print $1}')"
else
  artifact_sha="$(printf '0%.0s' {1..64})"
fi

size_hex="$(nm -S ./build/examples/simd-dot/dot.o 2>/dev/null | awk '$4=="simd_dot_f32"{print $2;exit}')"
if [[ -n "$size_hex" ]]; then
  code_size="$((16#$size_hex))"
else
  code_size=0
fi

export EVIDENCE_TMP="$tmp"
export EVIDENCE_OUT="$OUT"
export EVIDENCE_AFFINITY="$affinity"
export EVIDENCE_CPU_VENDOR="$cpu_vendor"
export EVIDENCE_CPU_MODEL="$cpu_model"
export EVIDENCE_MICROCODE="$microcode"
export EVIDENCE_KERNEL="$kernel"
export EVIDENCE_GOVERNOR="$governor"
export EVIDENCE_ARTIFACT_SHA="$artifact_sha"
export EVIDENCE_CODE_SIZE="$code_size"

python3 - <<'PY'
import json
import os
import statistics
from pathlib import Path

tmp = Path(os.environ["EVIDENCE_TMP"])

def parse(path):
    out = {}
    for line in path.read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            out[key] = value
    return out

samples = [parse(p) for p in sorted(tmp.glob("*.txt"), key=lambda p: int(p.stem))]
if not samples:
    raise SystemExit("no benchmark samples")

if any(s.get("correctness") != "pass" for s in samples):
    raise SystemExit("correctness failed")

scalar = [int(s["scalar_total_ns"]) for s in samples]
simd = [int(s["simd_total_ns"]) for s in samples]

n = int(samples[0]["n"])
iterations = int(samples[0]["iterations"])
warmup = int(samples[0]["warmup"])

median_scalar = int(statistics.median(scalar))
median_simd = int(statistics.median(simd))

ns_per_call = median_simd / iterations
ns_per_element = median_simd / (iterations * n)
speedup = median_scalar / median_simd
elements_per_second = iterations * n * 1e9 / median_simd
gflops = iterations * n * 2 / median_simd

data = {
    "schema": "asmory-performance-evidence-v1",
    "package": "simd-dot",
    "version": "0.1.0",
    "variant": "x86_64-avx2-generic",
    "artifact": {
        "sha256": os.environ["EVIDENCE_ARTIFACT_SHA"]
    },
    "benchmark": {
        "id": "simd-dot/dot-f32-v1",
        "primary_metric": "ns_per_element",
        "direction": "lower",
        "baseline": "scalar",
        "workload": {
            "operation": "dot-product",
            "dtype": "f32",
            "length": n,
            "dataset": "constant-1.0x0.5"
        }
    },
    "machine": {
        "arch": "x86_64",
        "cpu_vendor": os.environ["EVIDENCE_CPU_VENDOR"],
        "cpu_model": os.environ["EVIDENCE_CPU_MODEL"],
        "microcode": os.environ["EVIDENCE_MICROCODE"],
        "kernel": os.environ["EVIDENCE_KERNEL"],
        "affinity": os.environ["EVIDENCE_AFFINITY"],
        "governor": os.environ["EVIDENCE_GOVERNOR"]
    },
    "measurement": {
        "timer": samples[0]["timer"],
        "samples": len(samples),
        "warmup": warmup,
        "iterations": iterations
    },
    "metrics": {
        "median_scalar_total_ns": median_scalar,
        "median_simd_total_ns": median_simd,
        "ns_per_call": ns_per_call,
        "ns_per_element": ns_per_element,
        "elements_per_second": elements_per_second,
        "gflops": gflops,
        "speedup_vs_scalar": speedup,
        "code_size_bytes": int(os.environ["EVIDENCE_CODE_SIZE"])
    },
    "raw_samples": {
        "scalar_total_ns": scalar,
        "simd_total_ns": simd
    }
}

out = Path(os.environ["EVIDENCE_OUT"])
out.write_text(json.dumps(data, indent=2) + "\n")

print()
print("Summary")
print(f"  CPU             {data['machine']['cpu_model']}")
print(f"  ns / element    {ns_per_element:.4f}")
print(f"  GFLOP/s         {gflops:.3f}")
print(f"  vs scalar       {speedup:.3f}x")
print(f"  code size       {data['metrics']['code_size_bytes']} B")
print(f"  evidence        {out}")
PY
