#!/usr/bin/env bash
set -euo pipefail

ROOT="${ASMORY_ROOT:-$PWD}"
cd "$ROOT"

BIN="$ROOT/build/asmory"
HELPER="$ROOT/build/asmory-acquire"
REGISTRY="$ROOT/build/asmory-registry"
BASE="http://127.0.0.1:18080"
LOG="$ROOT/build/asmory-acquire-smoke-registry.log"

for x in "$BIN" "$HELPER" "$REGISTRY"; do
  [[ -x "$x" ]] || { echo "acquire-smoke: missing executable: $x" >&2; exit 2; }
done

command -v curl >/dev/null
command -v sha256sum >/dev/null

mapfile -t stale < <(pgrep -x asmory-registry || true)
if ((${#stale[@]})); then
  kill "${stale[@]}" 2>/dev/null || true
  for _ in $(seq 1 40); do
    alive=0
    for pid in "${stale[@]}"; do
      kill -0 "$pid" 2>/dev/null && alive=1 || true
    done
    (( alive == 0 )) && break
    sleep 0.05
  done
fi

if command -v ss >/dev/null 2>&1; then
  if ss -ltn "sport = :18080" | awk 'NR>1{found=1} END{exit !found}'; then
    echo "acquire-smoke: port 18080 remains occupied" >&2
    ss -ltnp "sport = :18080" >&2 || true
    exit 1
  fi
fi

"$REGISTRY" >"$LOG" 2>&1 &
PID=$!
tmp="$(mktemp -d)"
cleanup() {
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

ready=0
for _ in $(seq 1 60); do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "acquire-smoke: current registry died" >&2
    cat "$LOG" >&2 || true
    exit 1
  fi
  if curl -fsS "$BASE/" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.05
done
[[ "$ready" == 1 ]]

export PATH="$ROOT/build:$PATH"
export ASMORY_REGISTRY_URL="$BASE"

echo "== workspace required =="
mkdir -p "$tmp/no-workspace"
cd "$tmp/no-workspace"
set +e
"$BIN" acquire simd-dot artifact.tar.gz >"$tmp/no-workspace.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 9 ]]
grep -q 'asmory init' "$tmp/no-workspace.out"
[[ ! -e artifact.tar.gz ]]

echo "== verified acquisition =="
mkdir -p "$tmp/project"
cd "$tmp/project"
"$BIN" init >/dev/null

manifest_before="$(sha256sum asm.toml | awk '{print $1}')"
lock_before="$(sha256sum asm.lock | awk '{print $1}')"

"$BIN" acquire simd-dot simd-dot-0.1.0.tar.gz | tee "$tmp/acquire.out"
grep -q '^Artifact acquired$' "$tmp/acquire.out"
grep -q 'verification exact' "$tmp/acquire.out"

expected="$(sha256sum "$ROOT/build/packages/simd-dot-0.1.0.tar.gz" | awk '{print $1}')"
actual="$(sha256sum simd-dot-0.1.0.tar.gz | awk '{print $1}')"
[[ "$expected" == "$actual" ]]
[[ "$manifest_before" == "$(sha256sum asm.toml | awk '{print $1}')" ]]
[[ "$lock_before" == "$(sha256sum asm.lock | awk '{print $1}')" ]]

tar -tzf simd-dot-0.1.0.tar.gz | grep -q '^simd-dot/src/dot.S$'
[[ ! -e simd-dot ]]

echo "== no overwrite =="
printf 'sentinel\n' > existing.bin
sentinel="$(sha256sum existing.bin | awk '{print $1}')"
set +e
"$BIN" acquire simd-dot existing.bin >"$tmp/existing.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 12 ]]
[[ "$sentinel" == "$(sha256sum existing.bin | awk '{print $1}')" ]]

echo "== digest mismatch is fail-closed =="
bad_sha="$(printf '0%.0s' {1..64})"
set +e
"$HELPER" simd-dot 0.1.0 "$bad_sha" bad.tar.gz >"$tmp/bad.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 11 ]]
grep -q 'SHA-256 mismatch' "$tmp/bad.out"
[[ ! -e bad.tar.gz ]]

echo "== plaintext remote HTTP rejected before transport =="
set +e
ASMORY_REGISTRY_URL="http://example.com" \
  "$HELPER" simd-dot 0.1.0 "$expected" remote.tar.gz >"$tmp/http.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 9 ]]
grep -q 'refusing non-loopback plaintext HTTP' "$tmp/http.out"
[[ ! -e remote.tar.gz ]]

echo "acquire-smoke: ok"
