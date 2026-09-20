#!/usr/bin/env bash
set -euo pipefail

BIN="${1:-./build/asmory}"

"$BIN" --version | grep -q '^asmory '
"$BIN" target | grep -q '^Asmory host target'
"$BIN" target | grep -q 'arch         x86_64'
"$BIN" target | grep -q 'baseline     x86-64-v'
"$BIN" search simd | grep -q 'simd-dot'
"$BIN" info simd-dot | grep -q '^simd-dot 0.1.0'

if "$BIN" info definitely-not-a-package >/dev/null 2>&1; then
  echo 'expected unknown package lookup to fail' >&2
  exit 1
fi

echo 'cli-smoke: ok'
