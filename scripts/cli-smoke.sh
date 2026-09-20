#!/usr/bin/env bash
set -euo pipefail

BIN="${1:-./build/asmory}"

"$BIN" --version | grep -q '^asmory '
target="$("$BIN" target)"
grep -q '^Asmory host target' <<<"$target"
grep -q 'arch         x86_64' <<<"$target"
grep -q 'baseline     x86-64-v' <<<"$target"

"$BIN" search simd | grep -q 'simd-dot'
"$BIN" info simd-dot | grep -q '^simd-dot 0.1.0'
"$BIN" versions simd-dot | grep -q '^simd-dot releases'

explain="$("$BIN" explain simd-dot)"
grep -q '^Resolution explanation' <<<"$explain"
grep -q 'source-preferred' <<<"$explain"
grep -q 'leaf' <<<"$explain"
grep -q 'x86_64-avx2-generic' <<<"$explain"
grep -q 'stable fallback; no accepted comparable evidence' <<<"$explain"

audit="$("$BIN" audit simd-dot)"
grep -q '^Artifact and review status' <<<"$audit"
grep -q 'local integrity.*not evaluated' <<<"$audit"
grep -q 'review.*unreviewed' <<<"$audit"
grep -q 'advisories.*none known' <<<"$audit"
grep -q 'Exact Artifact != Safe Artifact' <<<"$audit"

evidence="$("$BIN" evidence simd-dot)"
grep -q '^Performance Evidence' <<<"$evidence"
grep -q 'simd-dot/dot-f32-v1' <<<"$evidence"
grep -q 'accepted.*0' <<<"$evidence"
grep -q 'no-accepted-current-artifact-evidence' <<<"$evidence"
grep -q 'stable fallback; no accepted comparable evidence' <<<"$evidence"

if grep -q 'avx2       yes' <<<"$target" && grep -q 'fma        yes' <<<"$target"; then
  resolved="$("$BIN" resolve simd-dot)"
  grep -q '^Resolved dependency' <<<"$resolved"
  grep -q 'result.*compatible' <<<"$resolved"
  grep -q 'variant.*x86_64-avx2-generic' <<<"$resolved"
  grep -Eq 'sha256[[:space:]]+[0-9a-f]{64}$' <<<"$resolved"
else
  if "$BIN" resolve simd-dot >/dev/null 2>&1; then
    echo 'expected incompatible host resolution to fail' >&2
    exit 1
  fi
fi

for cmd in info versions resolve explain audit evidence; do
  if "$BIN" "$cmd" definitely-not-a-package >/dev/null 2>&1; then
    echo "expected unknown package lookup to fail: $cmd" >&2
    exit 1
  fi
done

echo 'cli-smoke: ok'
