#!/usr/bin/env bash
set -euo pipefail

if [[ -r /proc/cpuinfo ]]; then
  flags="$(awk -F: '/^flags/{print $2; exit}' /proc/cpuinfo)"
  if ! grep -qw avx2 <<<"$flags" || ! grep -qw fma <<<"$flags"; then
    echo "conformance: SKIP (host lacks AVX2/FMA)"
    exit 0
  fi
fi

run_one() {
  local name="$1"
  local bin="$2"

  echo "== $name =="
  out="$("$bin")"
  printf '%s\n' "$out"

  grep -q '^contract=asmory/simd-dot-core@1.0.0$' <<<"$out"
  grep -q '^conformance=pass$' <<<"$out"
  grep -q '^cases=9$' <<<"$out"
}

run_one "x86_64-avx2-generic" ./build/conformance/simd-dot/generic
run_one "x86_64-avx2-fma-4acc" ./build/conformance/simd-dot/4acc

echo "conformance: both Variants satisfy the same Contract basic suite"
