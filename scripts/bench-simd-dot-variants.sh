#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="./build/benchmarks/simd-dot-variants"
OUT="./build/performance/simd-dot-variants.json"
SAMPLES="${ASMORY_PERF_SAMPLES:-11}"

mkdir -p "$(dirname "$OUT")"

runner=("$BIN")
affinity="unbound"
if command -v taskset >/dev/null 2>&1 && [[ -r /proc/self/status ]]; then
  allowed="$(awk '/^Cpus_allowed_list:/{sub(/^[^:]*:[[:space:]]*/,"");print;exit}' /proc/self/status)"
  first_range="${allowed%%,*}"
  cpu="${first_range%%-*}"
  if [[ "$cpu" =~ ^[0-9]+$ ]] && taskset -c "$cpu" true >/dev/null 2>&1; then
    runner=(taskset -c "$cpu" "$BIN")
    affinity="cpu:$cpu"
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Asmory Variant A/B"
echo "  A: x86_64-avx2-generic"
echo "  B: x86_64-avx2-fma-4acc"
echo "  samples:  $SAMPLES"
echo "  affinity: $affinity"
echo

for ((i=1; i<=SAMPLES; i++)); do
  "${runner[@]}" >"$tmp/$i.txt"
  grep -q '^correctness=pass$' "$tmp/$i.txt"
  a="$(awk -F= '$1=="generic_total_ns"{print $2}' "$tmp/$i.txt")"
  b="$(awk -F= '$1=="acc4_total_ns"{print $2}' "$tmp/$i.txt")"
  printf '  sample %02d/%02d  generic=%s  4acc=%s ns\n' "$i" "$SAMPLES" "$a" "$b"
done

export VAR_TMP="$tmp"
export VAR_OUT="$OUT"
export VAR_AFFINITY="$affinity"
export VAR_CPU_VENDOR="$(awk -F: '/vendor_id/{sub(/^[ \t]+/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null || true)"
export VAR_CPU_MODEL="$(awk -F: '/model name/{sub(/^[ \t]+/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null || true)"
export VAR_KERNEL="$(uname -srmo)"
export VAR_GOVERNOR="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)"

python3 - <<'PY'
import json, os, statistics
from pathlib import Path

def parse(path):
    d = {}
    for line in path.read_text().splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            d[k] = v
    return d

tmp = Path(os.environ["VAR_TMP"])
rows = [parse(p) for p in sorted(tmp.glob("*.txt"), key=lambda p: int(p.stem))]
generic = [int(x["generic_total_ns"]) for x in rows]
acc4 = [int(x["acc4_total_ns"]) for x in rows]

a = int(statistics.median(generic))
b = int(statistics.median(acc4))
improvement = (a - b) / a * 100.0
winner = "x86_64-avx2-fma-4acc" if b < a else "x86_64-avx2-generic"

data = {
    "schema": "asmory-variant-comparison-v1",
    "package": "simd-dot",
    "version": "0.1.0",
    "machine": {
        "arch": "x86_64",
        "cpu_vendor": os.environ["VAR_CPU_VENDOR"],
        "cpu_model": os.environ["VAR_CPU_MODEL"],
        "kernel": os.environ["VAR_KERNEL"],
        "affinity": os.environ["VAR_AFFINITY"],
        "governor": os.environ["VAR_GOVERNOR"]
    },
    "benchmark": {
        "id": "simd-dot/dot-f32-v1",
        "samples": len(rows),
        "workload": {"dtype":"f32","length":int(rows[0]["n"])}
    },
    "variants": {
        "x86_64-avx2-generic": {"median_total_ns": a, "raw_total_ns": generic},
        "x86_64-avx2-fma-4acc": {"median_total_ns": b, "raw_total_ns": acc4}
    },
    "comparison": {
        "winner_on_this_machine": winner,
        "four_acc_improvement_percent": improvement,
        "generic_over_4acc_ratio": a / b
    }
}

out = Path(os.environ["VAR_OUT"])
out.write_text(json.dumps(data, indent=2) + "\n")

print()
print("Variant result")
print("  CPU              ", data["machine"]["cpu_model"])
print(f"  generic median    {a/1e6:.3f} ms")
print(f"  4acc median       {b/1e6:.3f} ms")
print(f"  4acc improvement  {improvement:+.2f}%")
print("  winner here       ", winner)
print("  evidence          ", out)
PY
