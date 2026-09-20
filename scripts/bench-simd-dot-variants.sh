#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="./build/benchmarks/simd-dot-variants"
OUT="${ASMORY_VARIANT_EVIDENCE_OUT:-./build/performance/simd-dot-variants.json}"
SAMPLES="${ASMORY_PERF_SAMPLES:-11}"
ARTIFACT="./build/packages/simd-dot-0.1.0.tar.gz"
CONTRACT="./examples/simd-dot/performance.toml"

mkdir -p "$(dirname "$OUT")"

[[ -x "$BIN" ]] || { echo "missing benchmark binary: $BIN" >&2; exit 2; }
[[ -f "$ARTIFACT" ]] || { echo "missing source Artifact: $ARTIFACT" >&2; exit 2; }
[[ -f "$CONTRACT" ]] || { echo "missing Performance Contract: $CONTRACT" >&2; exit 2; }

runner_prefix=()
affinity="unbound"
if command -v taskset >/dev/null 2>&1 && [[ -r /proc/self/status ]]; then
  allowed="$(awk '/^Cpus_allowed_list:/{sub(/^[^:]*:[[:space:]]*/,"");print;exit}' /proc/self/status)"
  first_range="${allowed%%,*}"
  cpu="${first_range%%-*}"
  if [[ "$cpu" =~ ^[0-9]+$ ]] && taskset -c "$cpu" true >/dev/null 2>&1; then
    runner_prefix=(taskset -c "$cpu")
    affinity="cpu:$cpu"
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Asmory Variant Performance Evidence"
echo "  A:         x86_64-avx2-generic"
echo "  B:         x86_64-avx2-fma-4acc"
echo "  benchmark: simd-dot/dot-f32-v1"
echo "  samples:   $SAMPLES"
echo "  affinity:  $affinity"
echo "  ordering:  alternating AB / BA"
echo

for ((i=1; i<=SAMPLES; i++)); do
  order="ab"
  args=()
  if (( i % 2 == 0 )); then
    order="ba"
    args=(ba)
  fi

  "${runner_prefix[@]}" "$BIN" "${args[@]}" >"$tmp/$i.txt"
  grep -q '^correctness=pass$' "$tmp/$i.txt"
  grep -q "^order=$order$" "$tmp/$i.txt"

  a="$(awk -F= '$1=="generic_total_ns"{print $2}' "$tmp/$i.txt")"
  b="$(awk -F= '$1=="acc4_total_ns"{print $2}' "$tmp/$i.txt")"
  printf '  sample %02d/%02d  order=%s  generic=%s  4acc=%s ns\n' \
    "$i" "$SAMPLES" "$order" "$a" "$b"
done

export VAR_TMP="$tmp"
export VAR_OUT="$OUT"
export VAR_AFFINITY="$affinity"
export VAR_CPU_VENDOR="$(awk -F: '/vendor_id/{sub(/^[ \t]+/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null || true)"
export VAR_CPU_MODEL="$(awk -F: '/model name/{sub(/^[ \t]+/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null || true)"
export VAR_MICROCODE="$(awk -F: '/microcode/{sub(/^[ \t]+/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null || true)"
export VAR_KERNEL="$(uname -srmo)"
export VAR_GOVERNOR="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)"
export VAR_ARTIFACT_SHA="$(sha256sum "$ARTIFACT" | awk '{print $1}')"
export VAR_ARTIFACT_SIZE="$(wc -c < "$ARTIFACT" | tr -d '[:space:]')"
export VAR_CONTRACT_SHA="$(sha256sum "$CONTRACT" | awk '{print $1}')"

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
if not rows:
    raise SystemExit("no benchmark samples")
if any(x.get("correctness") != "pass" for x in rows):
    raise SystemExit("correctness failed")

generic = [int(x["generic_total_ns"]) for x in rows]
acc4 = [int(x["acc4_total_ns"]) for x in rows]
orders = [x["order"] for x in rows]

a = int(statistics.median(generic))
b = int(statistics.median(acc4))
improvement = (a - b) / a * 100.0
faster = "x86_64-avx2-fma-4acc" if b < a else "x86_64-avx2-generic"

records = []
for i, row in enumerate(rows, 1):
    records.append({
        "sample": i,
        "order": row["order"],
        "generic_total_ns": int(row["generic_total_ns"]),
        "acc4_total_ns": int(row["acc4_total_ns"]),
    })

def med(values):
    return int(statistics.median(values)) if values else None

ab = [r for r in records if r["order"] == "ab"]
ba = [r for r in records if r["order"] == "ba"]

data = {
    "schema": "asmory-performance-evidence-v2",
    "status": "local-candidate",
    "package": "simd-dot",
    "version": "0.1.0",
    "artifact": {
        "kind": "source",
        "sha256": os.environ["VAR_ARTIFACT_SHA"],
        "size": int(os.environ["VAR_ARTIFACT_SIZE"]),
    },
    "benchmark": {
        "id": "simd-dot/dot-f32-v1",
        "contract_sha256": os.environ["VAR_CONTRACT_SHA"],
        "primary_metric": "total_ns",
        "direction": "lower",
        "workload": {
            "dtype": "f32",
            "length": int(rows[0]["n"]),
        },
        "protocol": {
            "timer": rows[0]["timer"],
            "warmup": int(rows[0]["warmup"]),
            "iterations": int(rows[0]["iterations"]),
            "sample_order": "alternating-ab-ba",
        },
    },
    "machine": {
        "arch": "x86_64",
        "cpu_vendor": os.environ["VAR_CPU_VENDOR"],
        "cpu_model": os.environ["VAR_CPU_MODEL"],
        "microcode": os.environ["VAR_MICROCODE"],
        "kernel": os.environ["VAR_KERNEL"],
        "affinity": os.environ["VAR_AFFINITY"],
        "governor": os.environ["VAR_GOVERNOR"],
    },
    "correctness": {
        "state": "pass",
        "samples": len(rows),
    },
    "variants": {
        "x86_64-avx2-generic": {
            "median_total_ns": a,
        },
        "x86_64-avx2-fma-4acc": {
            "median_total_ns": b,
        },
    },
    "order_diagnostics": {
        "ab_samples": len(ab),
        "ba_samples": len(ba),
        "generic_median_ab_ns": med([r["generic_total_ns"] for r in ab]),
        "generic_median_ba_ns": med([r["generic_total_ns"] for r in ba]),
        "acc4_median_ab_ns": med([r["acc4_total_ns"] for r in ab]),
        "acc4_median_ba_ns": med([r["acc4_total_ns"] for r in ba]),
    },
    "observation": {
        "scope": "this-machine-only",
        "faster_variant_here": faster,
        "four_acc_improvement_percent_here": improvement,
        "eligible_for_global_ranking": False,
    },
    "raw_samples": records,
}

out = Path(os.environ["VAR_OUT"])
out.write_text(json.dumps(data, indent=2) + "\n")

print()
print("Local evidence summary")
print("  CPU                ", data["machine"]["cpu_model"])
print(f"  generic median      {a/1e6:.3f} ms")
print(f"  4acc median         {b/1e6:.3f} ms")
print(f"  4acc improvement    {improvement:+.2f}%")
print("  faster here         ", faster)
print("  artifact            ", data["artifact"]["sha256"])
print("  contract             ", data["benchmark"]["contract_sha256"])
print("  evidence             ", out)
print()
print("This is a machine-local observation, not a global resolver verdict.")
PY
