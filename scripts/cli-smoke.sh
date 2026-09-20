#!/usr/bin/env bash
set -euo pipefail

BIN="${1:-./build/asmory}"

"$BIN" --version | grep -q '^asmory '
target="$("$BIN" target)"
grep -q '^Asmory host target' <<<"$target"
grep -q 'arch         x86_64' <<<"$target"

sem="$("$BIN" semantics simd-dot)"
grep -q '^Semantic identity' <<<"$sem"
grep -Eq 'fingerprint[[:space:]]+[0-9a-f]{64}$' <<<"$sem"
grep -q 'facets.*source of truth' <<<"$sem"
grep -q 'provider.*Asmory/Asmory' <<<"$sem"

core="$("$BIN" match simd-dot asmory/simd-dot-core@1.0.0)"
grep -q 'result.*compatible/exact' <<<"$core"

if "$BIN" match simd-dot asmory/simd-dot-strict@1.0.0 >/tmp/asmory-match-strict 2>&1; then
  echo 'expected strict semantic alternative to reject current implementation' >&2
  exit 1
fi
grep -q 'result.*rejected' /tmp/asmory-match-strict
grep -q 'reason.*numeric.absolute_error_max' /tmp/asmory-match-strict

"$BIN" evidence simd-dot | grep -q '^Performance Evidence'
"$BIN" audit simd-dot | grep -q 'Exact Artifact != Safe Artifact'
explain="$($BIN explain simd-dot)"
grep -Eq 'fingerprint[[:space:]]+[0-9a-f]{64}$' <<<"$explain"

if grep -q 'avx2       yes' <<<"$target" && grep -q 'fma        yes' <<<"$target"; then
  "$BIN" resolve simd-dot | grep -q '^Resolved dependency'
fi

for cmd in info versions resolve explain audit evidence semantics; do
  if "$BIN" "$cmd" definitely-not-a-package >/dev/null 2>&1; then
    echo "expected unknown package lookup to fail: $cmd" >&2
    exit 1
  fi
done

echo 'cli-smoke: ok'
