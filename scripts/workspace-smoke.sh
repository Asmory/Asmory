#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
BIN="$(readlink -f "${ASMORY_CLI_BIN:-$ROOT/build/asmory}")"

[[ -x "$BIN" ]] || {
  echo "workspace-smoke: missing CLI: $BIN" >&2
  exit 2
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

project="$tmp/project"
mkdir -p "$project"
cd "$project"

echo "== fresh init =="
"$BIN" init

[[ -f asm.toml ]]
[[ -f asm.lock ]]
[[ -d .asmory/deps ]]
[[ -f .asmory/.gitignore ]]

grep -q '^schema = 1$' asm.toml
grep -q '^\[workspace\]$' asm.toml
grep -q '^\[dependencies\]$' asm.toml
grep -q '^resolver_policy = "asmory-v1"$' asm.toml

grep -q '^schema = 1$' asm.lock
grep -q '^resolver_policy = "asmory-v1"$' asm.lock
grep -q '^dependency_count = 0$' asm.lock
grep -q '^deps/$' .asmory/.gitignore
grep -q '^\.staging/$' .asmory/.gitignore
grep -q '^\.restore/$' .asmory/.gitignore
grep -q '^\.delta/$' .asmory/.gitignore
grep -q '^\.vendor/$' .asmory/.gitignore
grep -q '^workspace\.lock$' .asmory/.gitignore

before_manifest="$(sha256sum asm.toml | awk '{print $1}')"
before_lock="$(sha256sum asm.lock | awk '{print $1}')"

echo "== idempotent init =="
second="$("$BIN" init)"
grep -q 'already initialized' <<<"$second"
[[ "$before_manifest" == "$(sha256sum asm.toml | awk '{print $1}')" ]]
[[ "$before_lock" == "$(sha256sum asm.lock | awk '{print $1}')" ]]

echo "== partial metadata refusal =="
partial="$tmp/partial"
mkdir -p "$partial"
cd "$partial"
printf '# pre-existing user file\n' > asm.toml

set +e
"$BIN" init >"$tmp/partial.out" 2>&1
rc=$?
set -e

[[ "$rc" -eq 6 ]]
grep -q 'refusing to overwrite partial workspace metadata' "$tmp/partial.out"
[[ ! -e asm.lock ]]
grep -q '^# pre-existing user file$' asm.toml

echo "workspace-smoke: ok"
